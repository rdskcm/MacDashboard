// Engine/AIRequest.swift
// Provider configuration + request/response building for the AI assistant (Block
// AI, Wave 1). Pure Foundation only (URLRequest/URL/JSONSerialization construction
// — no URLSession usage, no actual networking) — symlinked into the Checks target.
// CRITICAL INVARIANT: the API key must appear ONLY in a request header, never in
// the JSON body, under any key.

import Foundation

// Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
#if AI_ENABLED
enum AIProvider: String, Codable, CaseIterable { case anthropic, openaiCompatible }

struct AIProviderConfig: Equatable {
    var provider: AIProvider
    var baseURL: String
    var model: String

    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .anthropic:
            if trimmed.isEmpty { return "https://api.anthropic.com" }
            return stripTrailingSlash(trimmed)
        case .openaiCompatible:
            return stripTrailingSlash(trimmed)
        }
    }

    var isComplete: Bool {
        let modelTrimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTrimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !modelTrimmed.isEmpty && (provider == .anthropic || !baseTrimmed.isEmpty)
    }

    private func stripTrailingSlash(_ s: String) -> String {
        s.hasSuffix("/") ? String(s.dropLast()) : s
    }
}

enum AIClientError: Error, Equatable {
    case notConfigured
    case keyUnavailable
    case badURL
    case network(String)
    case http(Int, String)
    case parse
}

enum AIRequestBuilder {
    static func buildRequest(config: AIProviderConfig, apiKey: String, system: String, payload: String) -> URLRequest? {
        let path: String
        switch config.provider {
        case .anthropic: path = "/v1/messages"
        case .openaiCompatible: path = "/v1/chat/completions"
        }
        guard let url = URL(string: config.effectiveBaseURL + path) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any]
        switch config.provider {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": config.model,
                "max_tokens": 4096,
                "system": system,
                "messages": [["role": "user", "content": payload]],
            ]
        case .openaiCompatible:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": config.model,
                "max_tokens": 4096,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": payload],
                ],
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = data
        return request
    }

    static func parseSuccess(_ data: Data, provider: AIProvider) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch provider {
        case .anthropic:
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            let text = content
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            return text.isEmpty ? nil : text
        case .openaiCompatible:
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  !content.isEmpty
            else { return nil }
            return content
        }
    }

    static func parseError(_ data: Data, provider: AIProvider) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch provider {
        case .anthropic:
            guard let error = json["error"] as? [String: Any],
                  let message = error["message"] as? String
            else { return nil }
            return message
        case .openaiCompatible:
            guard let error = json["error"] as? [String: Any],
                  let message = error["message"] as? String
            else { return nil }
            return message
        }
    }
}
#endif
