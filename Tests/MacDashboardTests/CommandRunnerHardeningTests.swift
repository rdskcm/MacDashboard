// Tests/MacDashboardTests/CommandRunnerHardeningTests.swift
// Port of Checks/main.swift lines 2459-2499 (CHECKS-SWIFT-TESTING).
import Foundation
import Testing
@testable import MacDashboard

extension SerialTests {
    struct CommandRunnerHardeningTests {
        @Test func hardening() async {
            // =====================================================================
            // MARK: - CommandRunner hardening (Block B7)
            // =====================================================================
            do {
                // F3: a single invalid UTF-8 byte in stdout must not discard the whole
                // capture — `run` uses the lossy decoder now, same as `run(onLine:)`.
                let invalidUTF8 = await runCommand("/bin/sh", ["-c", "printf 'a\\xffb\\n'"], timeout: 5).text
                #expect(invalidUTF8 != nil, "CommandRunner.run(...).text: invalid UTF-8 byte in stdout ⇒ non-nil")
                #expect(invalidUTF8?.contains("a") == true && invalidUTF8?.contains("b") == true,
                      "CommandRunner.run(...).text: invalid UTF-8 byte in stdout ⇒ surrounding valid text preserved")

                // F2: output beyond the 8 MiB cap is truncated, not lost or turned into a
                // timeout (the child must still be drained to EOF and exit normally).
                let over = await runCommand("/bin/sh", ["-c", "head -c 9000000 /dev/zero | tr '\\0' 'x'"], timeout: 10)
                #expect(over.text != nil, "CommandRunner.run: output over the cap ⇒ text != nil")
                #expect(over.stdoutTruncated == true, "CommandRunner.run: output over the cap ⇒ stdoutTruncated == true")
                #expect(over.stdout.utf8.count == CommandRunner.outputCap,
                      "CommandRunner.run: output over the cap ⇒ byte count == outputCap")

                // F2: output under the cap must not have `stdoutTruncated` stuck on.
                let under = await runCommand("/bin/sh", ["-c", "echo hello"], timeout: 5)
                #expect(under.text != nil, "CommandRunner.run: output under the cap ⇒ text != nil")
                #expect(under.stdoutTruncated == false, "CommandRunner.run: output under the cap ⇒ stdoutTruncated == false")

                // F4: the pinned default environment reaches the child, and an explicit
                // `environment:` override is actually applied (not ignored).
                let envOutput = await runCommand("/usr/bin/env", [], timeout: 5).text
                #expect(envOutput?.contains("LC_ALL=C") == true, "CommandRunner.run: default environment pins LC_ALL=C")
                #expect(envOutput?.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin") == true,
                      "CommandRunner.run: default environment pins PATH")

                var customEnv = CommandRunner.defaultEnvironment
                customEnv["MACDASHBOARD_CHECKS_VAR"] = "b7-marker"
                let customOutput = await runCommand("/usr/bin/env", [], timeout: 5, environment: customEnv).text
                #expect(customOutput?.contains("MACDASHBOARD_CHECKS_VAR=b7-marker") == true,
                      "CommandRunner.run: explicit environment: override is applied to the child")

                let prepended = CommandRunner.environment(prependingPATH: ["/custom/prefix/bin"])
                #expect(prepended["PATH"] == "/custom/prefix/bin:" + (CommandRunner.defaultEnvironment["PATH"] ?? ""),
                      "CommandRunner.environment(prependingPATH:): prepends given dir and keeps the rest of PATH")
            }
        }
    }
}
