// Engine/AIClient.swift
// Real networking client for the AI assistant (Block AI, Wave 4). Impure Engine —
// performs an actual URLSession request, so it is NOT symlinked into the Checks
// target (no fake-URLSession pattern exists in this codebase for round-trip
// testing; the request/response *building* logic already has Checks coverage via
// AIRequestBuilder in AIRequest.swift, which is pure and symlinked).
// CRITICAL INVARIANT: this file must never log, print, or persist the request,
// response body, payload, or API key anywhere — it carries a real API key and the
// user's diagnostic report.

import Foundation

// Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
#if AI_ENABLED
enum AIClient {
    static func send(payload: String, system: String, config: AIProviderConfig, apiKey: String) async -> Result<String, AIClientError> {
        guard let request = AIRequestBuilder.buildRequest(config: config, apiKey: apiKey, system: system, payload: payload) else {
            return .failure(.badURL)
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: sessionConfig)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            return .failure(.network(urlError.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.network("no HTTP response"))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            return .failure(.http(httpResponse.statusCode, AIRequestBuilder.parseError(data, provider: config.provider) ?? ""))
        }

        guard let text = AIRequestBuilder.parseSuccess(data, provider: config.provider), !text.isEmpty else {
            return .failure(.parse)
        }

        return .success(text)
    }
}
#endif
