// Tests/MoonportTests/ReaderStatusTests.swift
// READER-STATUS S1: reason texts, ordering, Mac identifiers and the generic command rule. Pure, no process-wide state.
import Foundation
import Testing
@testable import Moonport

struct ReaderStatusTests {
    static let kern: Int32 = -536870212

    static var reasons: [(ReaderReason, String)] {
        [
            (.libraryNotLoaded(path: "/x", dlerror: String(repeating: "a", count: 300)), "dlopen /x failed: " + String(repeating: "a", count: 200)),
            (.libraryNotLoaded(path: "/x", dlerror: nil), "dlopen /x failed: no dlerror text"),
            (.symbolMissing(library: "/L", symbol: "S"), "dlsym S not found in /L"),
            (.serviceAbsent(className: "AppleSMC"), "IOService AppleSMC not found"),
            (.registryEntryAbsent(path: "IODeviceTree:/cpus"), "registry entry IODeviceTree:/cpus not found"),
            (.registryPropertyAbsent(entry: "IOAccelerator", property: "gpu-core-count"), "registry property gpu-core-count not found on IOAccelerator"),
            (.ioReportChannelAbsent(group: "G", subgroup: "S", channel: nil), "IOReport group \"G\" / \"S\" not found"),
            (.ioReportChannelAbsent(group: "G", subgroup: "S", channel: "ECPU"), "IOReport channel ECPU not found in \"G\" / \"S\""),
            (.smcKeyAbsent(key: "TCMz", result: 0x84), "SMC key TCMz not found (result 0x84)"),
            (.smcKeyUnsupported(key: "PSTR", type: "flt ", size: 4), "SMC key PSTR has type \"flt \" size 4, not decodable"),
            (.smcResult(key: "PSTR", result: 0x0A), "SMC key PSTR read failed (result 0x0A)"),
            (.kernReturn(call: "IOServiceOpen(AppleSMC)", code: kern),
             "IOServiceOpen(AppleSMC) returned kern_return 0xE00002BC (" + String(cString: mach_error_string(kern)) + ")"),
            (.errno(call: "sysctlbyname(vm.swapusage)", code: 2), "sysctlbyname(vm.swapusage) failed: errno 2 (No such file or directory)"),
            (.nsError(call: "URL.resourceValues(/)", domain: "NSCocoaErrorDomain", code: 260), "URL.resourceValues(/) failed: NSCocoaErrorDomain 260"),
            (.callFailed(call: "getloadavg", code: 1), "getloadavg returned 1"),
            (.nullResult(call: "IOPSCopyPowerSourcesInfo"), "IOPSCopyPowerSourcesInfo returned NULL"),
            (.command(tool: "pmset -g batt", termination: .exited(3)), "pmset -g batt exited with status 3"),
            (.command(tool: "pmset -g batt", termination: .signaled(9)), "pmset -g batt killed by signal 9"),
            (.command(tool: "pmset -g batt", termination: .launchFailed(2)), "pmset -g batt could not start: errno 2 (No such file or directory)"),
            (.command(tool: "pmset -g batt", termination: .timedOut), "pmset -g batt timed out"),
            (.command(tool: "pmset -g batt", termination: .cancelled), "pmset -g batt cancelled"),
            (.emptyOutput(tool: "diskutil list"), "diskutil list printed nothing"),
            (.unparsed(tool: "diskutil list"), "diskutil list output not recognised"),
            (.executableAbsent(name: "smartctl", searched: ["/a/smartctl", "/b/smartctl"]), "smartctl not found at /a/smartctl, /b/smartctl"),
            (.empty(what: "HID temperature services"), "HID temperature services: none found"),
            (.implausible(what: "PSTR", value: "1200.00 W", accepted: "(0, 1000] W"), "PSTR = 1200.00 W, outside (0, 1000] W"),
            (.validationFailed(what: "core topology", check: "perflevel core sum 9 == activeProcessorCount 10"),
             "core topology failed check: perflevel core sum 9 == activeProcessorCount 10"),
            (.prerequisiteFailed(reader: .smcConnection), "not run because smc.connection failed"),
            (.timedOut(seconds: 10), "no answer within 10 s"),
            (.several([.timedOut(seconds: 10), .nullResult(call: "X")]), "no answer within 10 s | X returned NULL"),
        ]
    }

    @Test func reasonTexts() {
        for (reason, text) in Self.reasons {
            #expect(reason.text == text)
        }
    }

    @Test func noReasonTextHasASemicolon() {
        for (reason, _) in Self.reasons {
            #expect(!reason.text.contains(";"))
        }
    }

    @Test func joinedKeepsASingleReason() {
        let r1 = ReaderReason.nullResult(call: "A")
        let r2 = ReaderReason.empty(what: "B")
        #expect(ReaderReason.joined([r1]) == r1)
        #expect(ReaderReason.joined([r1, r2]).text == r1.text + " | " + r2.text)
    }

    @Test func orderedFollowsTheOrderThenRawValue() {
        let lines = [ReaderStatusLine(reader: ReaderID("z.unknown"), status: .ok),
                     ReaderStatusLine(reader: .smcPower, status: .ok),
                     ReaderStatusLine(reader: .systemVersion, status: .ok),
                     ReaderStatusLine(reader: ReaderID("a.unknown"), status: .ok)]
        #expect(ReaderStatusLine.ordered(lines, by: ReaderID.macOrder).map(\.reader.rawValue)
                == ["system.version", "smc.power", "a.unknown", "z.unknown"])
    }

    @Test func macOrderHas27UniqueIDs() {
        #expect(ReaderID.macOrder.count == 27)
        #expect(Set(ReaderID.macOrder).count == 27)
        #expect(ReaderID.macOrder.first?.rawValue == "system.version")
        #expect(ReaderID.macOrder.last?.rawValue == "disk.externalList")
    }

    @Test func commandStatusRule() {
        func s(_ t: CommandOutcome.Termination, _ out: String, _ parsed: Bool) -> ReaderStatus {
            ReaderStatusMac.commandStatus(tool: "t", termination: t, stdout: out, parsed: parsed)
        }
        #expect(s(.launchFailed(2), "x", true) == .failed(.command(tool: "t", termination: .launchFailed(2))))
        #expect(s(.timedOut, "x", true) == .failed(.command(tool: "t", termination: .timedOut)))
        #expect(s(.cancelled, "x", true) == .failed(.command(tool: "t", termination: .cancelled)))
        #expect(s(.signaled(9), " \n", true) == .failed(.command(tool: "t", termination: .signaled(9))))
        #expect(s(.signaled(9), "out", true) == .ok)
        #expect(s(.exited(0), "\n", true) == .failed(.emptyOutput(tool: "t")))
        #expect(s(.exited(1), "", true) == .failed(.command(tool: "t", termination: .exited(1))))
        #expect(s(.exited(4), "out", true) == .ok)
        #expect(s(.exited(0), "out", false) == .failed(.unparsed(tool: "t")))

        let ok = ReaderStatusMac.commandLine(.batteryPmset, tool: "t", termination: .exited(0), stdout: "x", parsed: true, reading: "charge 80%")
        #expect(ok.reading == "charge 80%")
        let bad = ReaderStatusMac.commandLine(.batteryPmset, tool: "t", termination: .exited(0), stdout: "x", parsed: false, reading: "charge 80%")
        #expect(bad.reading == nil)
    }
}
