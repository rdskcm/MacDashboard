// Views/AIAskSheet.swift
// "Ask AI" sheet (Block AI, Wave 3): shows the exact (redacted) payload that would
// be sent, lets the user toggle which sensitive values get redacted, and wires a
// Send button to a state machine. The actual network call is a STUB in this wave
// (Wave 4 replaces it with a real AIClient.send) — this sheet only proves the UI
// and state machine work end-to-end.

import SwiftUI

// Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
#if AI_ENABLED
struct AIAskSheet: View {
    let model: DashboardModel

    private enum Phase: Equatable {
        case composing
        case sending
        case answered(String)
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var options = RedactionOptions()
    @State private var phase: Phase = .composing
    @State private var context = RedactionContext()
    @State private var rawPayload = ""

    private var redactedPayload: String {
        Redactor.redact(rawPayload, context: context, options: options)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.aiSheetTitle).font(.headline)
            Text(L.aiSheetPayloadCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(redactedPayload)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardBackground()

            VStack(alignment: .leading, spacing: 6) {
                // Not all four toggles are functionally equivalent yet — some are UI placeholders pending a redaction rework.
                Toggle(L.aiToggleSerials, isOn: $options.redactSerials)
                Toggle(L.aiToggleUsername, isOn: $options.redactUsername)
                Toggle(L.aiToggleHostname, isOn: $options.redactHostname)
                Toggle(L.aiToggleSSID, isOn: $options.redactSSID)
            }

            switch phase {
            case .composing, .sending:
                EmptyView()
            case .answered(let text):
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.aiAnswerTitle).font(.callout.weight(.semibold))
                    Text(text).font(.callout).textSelection(.enabled)
                }
            case .failed(let msg):
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Text(L.aiPrivacyContract)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L.adviceCancel) { dismiss() }
                Button {
                    send()
                } label: {
                    if phase == .sending {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L.aiSending)
                        }
                    } else {
                        Text(L.aiSendButton)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(phase == .sending)
            }
        }
        .padding(16)
        .frame(width: 640, height: 560)
        .onAppear {
            context = AISensitiveContext.collect()
            rawPayload = AIPayloadBuilder.build(AIPayloadInput(reportText: model.reportText, assessment: model.assessment, live: model.currentLiveSnapshot()))
        }
    }

    private func send() {
        phase = .sending
        let payloadToSend = redactedPayload
        Task {
            guard let apiKey = KeychainStore.read() else {
                phase = .failed(L.aiKeyReadFailed)
                return
            }
            let config = AppSettings.shared.aiConfig
            let result = await AIClient.send(payload: payloadToSend, system: L.aiSystemPrompt, config: config, apiKey: apiKey)
            switch result {
            case .success(let text):
                phase = .answered(text)
            case .failure(let error):
                phase = .failed(errorMessage(for: error))
            }
        }
    }

    private func errorMessage(for error: AIClientError) -> String {
        switch error {
        case .notConfigured: return L.aiRequestFailed("not configured")
        case .keyUnavailable: return L.aiKeyReadFailed
        case .badURL: return L.aiRequestFailed("bad URL")
        case .network(let msg): return L.aiRequestFailed(msg)
        case .http(let code, let msg): return L.aiRequestFailed(msg.isEmpty ? "HTTP \(code)" : msg)
        case .parse: return L.aiRequestFailed("could not parse response")
        }
    }
}
#endif
