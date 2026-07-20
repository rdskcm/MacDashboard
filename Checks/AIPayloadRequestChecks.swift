// Checks/AIPayloadRequestChecks.swift
// Pure-logic coverage for AIPayloadBuilder, AIProviderConfig and AIRequestBuilder
// (Block AI, Wave 1). Real check code (NOT a symlink — see README.md), following
// the same pattern as LaunchdPlistInspectorChecks.swift.

import Foundation

func runAIPayloadRequestChecks() {
    // 18: three banners in order, report section carries reportText verbatim
    do {
        let input = AIPayloadInput(reportText: "MY REPORT TEXT", assessment: Assessment(), live: LiveSnapshot())
        let payload = AIPayloadBuilder.build(input)
        let bannerAssessment = "===== \(L.aiPayloadSectionAssessment) ====="
        let bannerLive = "===== \(L.aiPayloadSectionLive) ====="
        let bannerReport = "===== \(L.aiPayloadSectionReport) ====="
        guard let iA = payload.range(of: bannerAssessment), let iL = payload.range(of: bannerLive), let iR = payload.range(of: bannerReport) else {
            check(false, "AIPayloadBuilder: all three banners present (got \(payload))")
            return
        }
        check(iA.lowerBound < iL.lowerBound && iL.lowerBound < iR.lowerBound,
              "AIPayloadBuilder: banners in order Assessment < Live < Report")
        check(payload.contains("MY REPORT TEXT"), "AIPayloadBuilder: report section carries reportText verbatim")
    }

    // 19: nil reportText -> aiNoReport, no literal "nil"
    do {
        let input = AIPayloadInput(reportText: nil, assessment: Assessment(), live: LiveSnapshot())
        let payload = AIPayloadBuilder.build(input)
        check(payload.contains(L.aiNoReport), "AIPayloadBuilder: nil reportText -> L.aiNoReport present")
        check(!payload.contains("nil"), "AIPayloadBuilder: nil reportText -> no literal 'nil' text (got \(payload))")
    }

    // 20: problems/tips lines, and empty assessment -> recommendationsAllGood
    do {
        var a = Assessment()
        a.problems = [Problem(sev: .warn, text: "Something is wrong")]
        a.tips = [Tip(text: "Do something")]
        let payload = AIPayloadBuilder.build(AIPayloadInput(reportText: "x", assessment: a, live: LiveSnapshot()))
        check(payload.contains("- [\(Severity.warn.rawValue)] Something is wrong"),
              "AIPayloadBuilder: problem line formatted '- [sev] text' (got \(payload))")
        check(payload.contains("\(L.aiPayloadTipPrefix)Do something"),
              "AIPayloadBuilder: tip line formatted with L.aiPayloadTipPrefix (got \(payload))")

        let emptyPayload = AIPayloadBuilder.build(AIPayloadInput(reportText: "x", assessment: Assessment(), live: LiveSnapshot()))
        check(emptyPayload.contains(L.recommendationsAllGood),
              "AIPayloadBuilder: empty assessment -> L.recommendationsAllGood (got \(emptyPayload))")
    }

    // 21: only disk populated -> disk line present, no battery/memory lines
    do {
        var live = LiveSnapshot()
        live.disk = DiskInfo(size: 1_000_000_000_000, avail: 500_000_000_000, dataUsed: nil, sysUsed: nil)
        let payload = AIPayloadBuilder.build(AIPayloadInput(reportText: "x", assessment: Assessment(), live: live))
        check(payload.contains("Disk:"), "AIPayloadBuilder: disk-only live -> disk line present (got \(payload))")
        check(!payload.contains("Battery"), "AIPayloadBuilder: disk-only live -> no battery line (got \(payload))")
        check(!payload.contains("Memory:"), "AIPayloadBuilder: disk-only live -> no memory line (got \(payload))")
    }

    // 22: AIProviderConfig effectiveBaseURL / isComplete
    do {
        let anthropicDefault = AIProviderConfig(provider: .anthropic, baseURL: "", model: "claude-opus-4-8")
        check(anthropicDefault.effectiveBaseURL == "https://api.anthropic.com",
              "AIProviderConfig: anthropic empty baseURL -> default (got \(anthropicDefault.effectiveBaseURL))")
        check(anthropicDefault.isComplete, "AIProviderConfig: anthropic with model -> isComplete true")

        let openaiEmpty = AIProviderConfig(provider: .openaiCompatible, baseURL: "", model: "gpt-4")
        check(!openaiEmpty.isComplete, "AIProviderConfig: openaiCompatible with empty baseURL -> isComplete false")

        let openaiTrailing = AIProviderConfig(provider: .openaiCompatible, baseURL: "https://x.example/", model: "gpt-4")
        check(openaiTrailing.effectiveBaseURL == "https://x.example",
              "AIProviderConfig: openaiCompatible strips trailing slash (got \(openaiTrailing.effectiveBaseURL))")
    }

    // 23: buildRequest anthropic shape
    do {
        let config = AIProviderConfig(provider: .anthropic, baseURL: "", model: "claude-opus-4-8")
        let system = "SYSTEM PROMPT"
        let payload = "USER PAYLOAD"
        guard let req = AIRequestBuilder.buildRequest(config: config, apiKey: "sk-test-123", system: system, payload: payload) else {
            check(false, "AIRequestBuilder.buildRequest: anthropic request built")
            return
        }
        check(req.url?.absoluteString == "https://api.anthropic.com/v1/messages",
              "AIRequestBuilder: anthropic URL (got \(String(describing: req.url)))")
        check(req.httpMethod == "POST", "AIRequestBuilder: anthropic method POST")
        check(req.value(forHTTPHeaderField: "x-api-key") == "sk-test-123", "AIRequestBuilder: anthropic x-api-key header")
        check(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "AIRequestBuilder: anthropic-version header")
        check(req.value(forHTTPHeaderField: "content-type") != nil, "AIRequestBuilder: content-type header present")

        if let body = req.httpBody, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            check(json["model"] as? String == config.model, "AIRequestBuilder: anthropic body model")
            check(json["max_tokens"] as? Int == 4096, "AIRequestBuilder: anthropic body max_tokens == 4096")
            check(json["system"] as? String == system, "AIRequestBuilder: anthropic body system present")
            let messages = json["messages"] as? [[String: Any]]
            check(messages?.first?["role"] as? String == "user", "AIRequestBuilder: anthropic messages[0].role == user")
            check(messages?.first?["content"] as? String == payload, "AIRequestBuilder: anthropic messages[0].content == payload")
        } else {
            check(false, "AIRequestBuilder: anthropic httpBody parses as JSON")
        }
    }

    // 24: key never appears in body (both providers)
    do {
        let anthropicConfig = AIProviderConfig(provider: .anthropic, baseURL: "", model: "m")
        let anthropicReq = AIRequestBuilder.buildRequest(config: anthropicConfig, apiKey: "sk-test-123", system: "s", payload: "p")
        if let body = anthropicReq?.httpBody, let str = String(data: body, encoding: .utf8) {
            check(!str.contains("sk-test-123"), "AIRequestBuilder: anthropic body never contains the API key")
        } else {
            check(false, "AIRequestBuilder: anthropic httpBody decodes as UTF-8")
        }

        let openaiConfig = AIProviderConfig(provider: .openaiCompatible, baseURL: "https://x.example", model: "m")
        let openaiReq = AIRequestBuilder.buildRequest(config: openaiConfig, apiKey: "sk-test-123", system: "s", payload: "p")
        if let body = openaiReq?.httpBody, let str = String(data: body, encoding: .utf8) {
            check(!str.contains("sk-test-123"), "AIRequestBuilder: openaiCompatible body never contains the API key")
        } else {
            check(false, "AIRequestBuilder: openaiCompatible httpBody decodes as UTF-8")
        }
    }

    // 25: openaiCompatible request shape
    do {
        let config = AIProviderConfig(provider: .openaiCompatible, baseURL: "https://x.example", model: "gpt-4")
        guard let req = AIRequestBuilder.buildRequest(config: config, apiKey: "sk-test-123", system: "SYS", payload: "PAY") else {
            check(false, "AIRequestBuilder.buildRequest: openaiCompatible request built")
            return
        }
        check(req.url?.absoluteString.hasSuffix("/v1/chat/completions") == true,
              "AIRequestBuilder: openaiCompatible URL ends with /v1/chat/completions (got \(String(describing: req.url)))")
        check(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-123",
              "AIRequestBuilder: openaiCompatible Authorization header")
        if let body = req.httpBody, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let messages = json["messages"] as? [[String: Any]]
            check(messages?.count == 2, "AIRequestBuilder: openaiCompatible has 2 messages")
            check(messages?[0]["role"] as? String == "system", "AIRequestBuilder: openaiCompatible messages[0].role == system")
            check(messages?[1]["role"] as? String == "user", "AIRequestBuilder: openaiCompatible messages[1].role == user")
        } else {
            check(false, "AIRequestBuilder: openaiCompatible httpBody parses as JSON")
        }
    }

    // 26: parseSuccess anthropic
    do {
        let single = Data(#"{"content":[{"type":"text","text":"Всё в порядке"}],"stop_reason":"end_turn"}"#.utf8)
        check(AIRequestBuilder.parseSuccess(single, provider: .anthropic) == "Всё в порядке",
              "AIRequestBuilder.parseSuccess: anthropic single text block")

        let multi = Data(#"{"content":[{"type":"text","text":"Часть 1. "},{"type":"text","text":"Часть 2."}]}"#.utf8)
        let joined = AIRequestBuilder.parseSuccess(multi, provider: .anthropic)
        check(joined == "Часть 1. Часть 2.", "AIRequestBuilder.parseSuccess: anthropic joins multiple text blocks (got \(String(describing: joined)))")

        let empty = Data(#"{"content":[]}"#.utf8)
        check(AIRequestBuilder.parseSuccess(empty, provider: .anthropic) == nil,
              "AIRequestBuilder.parseSuccess: anthropic empty content -> nil")
    }

    // 27: parseSuccess openaiCompatible
    do {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#.utf8)
        check(AIRequestBuilder.parseSuccess(data, provider: .openaiCompatible) == "ok",
              "AIRequestBuilder.parseSuccess: openaiCompatible choices[0].message.content")
    }

    // 28: parseError both providers + garbage
    do {
        let anthropicErr = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        check(AIRequestBuilder.parseError(anthropicErr, provider: .anthropic) == "invalid x-api-key",
              "AIRequestBuilder.parseError: anthropic error.message")

        let openaiErr = Data(#"{"error":{"message":"bad key"}}"#.utf8)
        check(AIRequestBuilder.parseError(openaiErr, provider: .openaiCompatible) == "bad key",
              "AIRequestBuilder.parseError: openaiCompatible error.message")

        let garbage = Data("not json at all {{{".utf8)
        check(AIRequestBuilder.parseError(garbage, provider: .anthropic) == nil,
              "AIRequestBuilder.parseError: garbage data -> nil, no crash")
    }
}
