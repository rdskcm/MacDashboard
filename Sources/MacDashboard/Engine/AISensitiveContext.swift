// Engine/AISensitiveContext.swift
// Collects best-effort, environment-dependent values (usernames, hostnames,
// hardware serial, Wi-Fi SSID) to feed into Redactor as a RedactionContext before
// sending a payload to the AI assistant (Block AI, Wave 3). Impure — talks to
// IOKit and spawns short-lived subprocesses — so this file is NOT symlinked into
// the Checks target. Foundation/IOKit only, no SwiftUI.
//
// Every individual collection step is independently best-effort: any failure
// (sandboxed environment, VM, missing binary, IOKit unavailable, no Wi-Fi) just
// skips that one value. `collect()` itself never throws and never crashes.

import Foundation
import IOKit

// Compiled out of the default (public) build — see Package.swift/build_app.sh (AI_ENABLED).
#if AI_ENABLED
enum AISensitiveContext {
    static func collect() -> RedactionContext {
        var context = RedactionContext()
        context.usernames = collectUsernames()
        context.hostNames = collectHostNames()
        context.serials = collectSerials()
        context.ssids = collectSSIDs()
        return context
    }

    // MARK: - Usernames

    private static func collectUsernames() -> [String] {
        [NSUserName(), NSFullUserName()].filter { !$0.isEmpty }
    }

    // MARK: - Host names

    private static func collectHostNames() -> [String] {
        var names: [String] = []

        let processHostName = ProcessInfo.processInfo.hostName
        if !processHostName.isEmpty {
            names.append(processHostName)
            if processHostName.hasSuffix(".local") {
                names.append(String(processHostName.dropLast(".local".count)))
            }
        }

        if let localHostName = CommandRunner.run("/usr/sbin/scutil", ["--get", "LocalHostName"], timeout: 2)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !localHostName.isEmpty {
            names.append(localHostName)
        }
        if let computerName = CommandRunner.run("/usr/sbin/scutil", ["--get", "ComputerName"], timeout: 2)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !computerName.isEmpty {
            names.append(computerName)
        }

        return names
    }

    // MARK: - Hardware serial

    private static func collectSerials() -> [String] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return [] }
        defer { IOObjectRelease(service) }

        guard let cfValue = IORegistryEntryCreateCFProperty(service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0) else {
            return []
        }
        guard let serial = cfValue.takeRetainedValue() as? String, !serial.isEmpty else { return [] }
        return [serial]
    }

    // MARK: - SSID (best-effort; not currently part of the actual payload text)

    private static func collectSSIDs() -> [String] {
        var ssids: [String] = []
        for interface in ["en0", "en1"] {
            guard let output = CommandRunner.run("/usr/sbin/ipconfig", ["getsummary", interface], timeout: 2) else { continue }
            for line in output.split(separator: "\n") {
                guard let range = line.range(of: "SSID :") else { continue }
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { ssids.append(value) }
            }
        }
        return ssids
    }
}
#endif
