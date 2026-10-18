// Engine/IPSWSources.swift
// IPHONE-IPSW: the two lookups behind their own buttons — Apple's version catalogue
// («Check with Apple») and ipsw.me («Ask ipsw.me», which sends the model identifier) —
// plus the HEAD that sizes a download when ipsw.me was not asked.
//
// network-stance (CONSTRAINTS-EVIDENCE.md): no telemetry; every request here runs only
// because the user clicked a control naming it. Each request has an EXACT host allowlist,
// a redirect off it is refused, sessions are ephemeral (no cookies, no disk cache), trust
// is the system's (no custom certificate evaluation), no retries, nothing persisted.
// A new host or a new field sent is a row in network-stance, SPEC.md §1.6 and both READMEs.

import Foundation

struct IPSWSources: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Injected so tests never touch the network. Live: ephemeral session + RedirectGuard.
    var fetch: Fetch

    static let live = IPSWSources(fetch: liveFetch(using: makeSession(redirectGuard: RedirectGuard())))

    static let catalogueHost = "itunes.apple.com"
    static let ipswMeHost = "api.ipsw.me"
    static let apiTimeout: TimeInterval = 15
    static let catalogueTimeout: TimeInterval = 30   // the catalogue is ~6 MB

    static func makeSession(redirectGuard: RedirectGuard) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
    }

    static func liveFetch(using session: URLSession) -> Fetch {
        { request in try await session.data(for: request) }
    }

    static var userAgent: String {
        "MacDashboard/" + ((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev")
    }

    static func request(_ url: URL, method: String = "GET", timeout: TimeInterval) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    // MARK: lookups

    /// «Check with Apple». The request is the same for every model; the identifier only
    /// selects the entry locally, but it is validated first like everywhere else.
    func appleTarget(identifier: String) async -> Result<IPSWAppleTarget?, IPSWError> {
        guard IPSWData.isValidIdentifier(identifier) else { return .failure(.badIdentifier(identifier)) }
        let req = Self.request(IPSWData.catalogueURL, timeout: Self.catalogueTimeout)
        switch await perform(req, allowedHost: Self.catalogueHost) {
        case .failure(let e): return .failure(e)
        case .success(let (data, response)):
            guard response.statusCode == 200 else { return .failure(.http(response.statusCode)) }
            return IPSWData.parseCatalogue(data, identifier: identifier)
        }
    }

    /// «Ask ipsw.me». Sends the model identifier (and only that) to api.ipsw.me.
    func ipswMe(identifier: String) async -> Result<IPSWThirdParty, IPSWError> {
        guard let url = IPSWData.ipswMeURL(identifier: identifier) else { return .failure(.badIdentifier(identifier)) }
        let req = Self.request(url, timeout: Self.apiTimeout)
        switch await perform(req, allowedHost: Self.ipswMeHost) {
        case .failure(let e): return .failure(e)
        case .success(let (data, response)):
            if response.statusCode == 404 { return .failure(.unknownDevice) }
            guard response.statusCode == 200 else { return .failure(.http(response.statusCode)) }
            return IPSWData.parseIPSWMe(data)
        }
    }

    /// HEAD on a firmware URL: its `Content-Length`, nil when absent. The URL must pass
    /// `downloadPolicy`, else no request is made.
    func head(_ url: URL) async -> Result<Int64?, IPSWError> {
        if let e = IPSWData.downloadPolicy(url) { return .failure(e) }
        let req = Self.request(url, method: "HEAD", timeout: Self.apiTimeout)
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        switch await perform(req, allowedHost: host) {
        case .failure(let e): return .failure(e)
        case .success(let (_, response)):
            guard response.statusCode == 200 else { return .failure(.http(response.statusCode)) }
            let header = response.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
            let length = header ?? response.expectedContentLength
            return .success(length > 0 ? length : nil)
        }
    }

    // MARK: transport

    /// One request: refuses before sending if the URL is not on `allowedHost`, maps a refused
    /// redirect (RedirectGuard hands back the 3xx) to `.notDownloadable(<target host>)`, and
    /// re-checks the final URL.
    func perform(_ req: URLRequest, allowedHost: String) async -> Result<(Data, HTTPURLResponse), IPSWError> {
        guard let url = req.url, url.scheme?.lowercased() == "https",
              url.host(percentEncoded: false)?.lowercased() == allowedHost
        else { return .failure(.notDownloadable(req.url?.host(percentEncoded: false) ?? "")) }
        do {
            let (data, response) = try await fetch(req)
            guard let http = response as? HTTPURLResponse else { return .failure(.badResponse) }
            if (300...399).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location") {
                let target = URL(string: location, relativeTo: url)?.absoluteURL
                return .failure(.notDownloadable(target?.host(percentEncoded: false) ?? location))
            }
            if let final = http.url, !RedirectGuard.allows(from: url, to: final) {
                return .failure(.notDownloadable(final.host(percentEncoded: false) ?? ""))
            }
            return .success((data, http))
        } catch {
            return .failure(Self.mapError(error))
        }
    }

    static func mapError(_ error: Error) -> IPSWError {
        if let e = error as? IPSWError { return e }
        if error is CancellationError { return .cancelled }
        guard let u = error as? URLError else { return .transfer(error.localizedDescription) }
        switch u.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        default: return .transfer(u.localizedDescription)   // incl. untrusted certificates: never bypassed
        }
    }
}

/// Redirect policy for every session in this feature (network-stance): an API request may
/// only be redirected to its own exact host; a firmware request only to an allowlisted
/// firmware host; always over https. A refused redirect is not followed (the 3xx comes back
/// and `perform` / the downloader turn it into `.notDownloadable`).
final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// Optional observer (the live canary prints every hop). Called on the session's queue.
    private let onHop: (@Sendable (URL, Bool) -> Void)?

    init(onHop: (@Sendable (URL, Bool) -> Void)? = nil) {
        self.onHop = onHop
    }

    static func allows(from original: URL, to target: URL) -> Bool {
        guard target.scheme?.lowercased() == "https",
              let to = target.host(percentEncoded: false)?.lowercased(),
              let from = original.host(percentEncoded: false)?.lowercased() else { return false }
        if IPSWData.firmwareHosts.contains(from) { return IPSWData.firmwareHosts.contains(to) }
        return to == from
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url else {
            completionHandler(nil)
            return
        }
        let ok = Self.allows(from: original, to: target)
        onHop?(target, ok)
        completionHandler(ok ? request : nil)
    }
}
