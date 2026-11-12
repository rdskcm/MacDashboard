import Testing
import Foundation
@testable import Moonport

extension SerialTests {
    @MainActor struct DiskReadLiveCanaryTests {
        // Opt-in: MACDASH_LIVE=1 swift test --filter liveCanaryDiskRead. Reads only: the volume capacity keys and `df -k`.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["MACDASH_LIVE"] == "1"))
        func liveCanaryDiskRead() async throws {
            let d = try #require(LiveCollector().collectFast().disk)
            let text = await CommandRunner.run("/bin/df", ["-k", "/System/Volumes/Data"], timeout: 10).text ?? ""
            let lines = text.split(separator: "\n")
            #expect(lines.count >= 2, "df output: \(text)")
            let cols = lines.count >= 2 ? lines[1].split(separator: " ", omittingEmptySubsequences: true) : []
            #expect(cols.count >= 4)
            let dfBlocks = cols.count >= 4 ? Int64(cols[1]) ?? 0 : 0
            let dfAvail = cols.count >= 4 ? Int64(cols[3]) ?? 0 : 0
            print("liveCanary disk size=\(d.size) avail=\(d.avail) purgeable=\(String(describing: d.purgeable)) dataUsed=\(String(describing: d.dataUsed)) sysUsed=\(String(describing: d.sysUsed)) df_blocks=\(dfBlocks) df_avail=\(dfAvail)")
            #expect(d.size > 0)
            #expect(0 < d.avail && d.avail < d.size)
            #expect(abs(d.size - dfBlocks * 1024) <= d.size / 100)
            #expect(d.avail + 2_000_000_000 >= dfAvail * 1024)
            #expect(d.purgeable.map { $0 < d.size } ?? true)
        }
    }
}
