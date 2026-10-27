// Engine/StoragePageModel.swift
// REDESIGN-STORAGE: pure state, texts, tones and thresholds of the Storage page (handoff 05-storage).
import Foundation
import CoreGraphics

enum SpaceLevel: Equatable, Sendable { case ok, low, critical }

/// The ONLY low-space rule (Assess, Home through Assess, Storage page). Source (user 2026-10-19): hot 10 % ≈ the
/// 25–35 GB free a macOS update needs on a 256 GB disk (third-party estimates; Apple publishes none); amber
/// 20 % default = SSD free-space headroom (vendor over-provisioning guidance).
enum StorageSpace {
    static let criticalPercent = 10
    /// Critical first: with lowPercent == 10 there is no amber band. Strict less-than, integer maths.
    /// `Double` avoids `Int64` overflow at `avail * 100`; the comparison is exact for byte counts below 2^53.
    static func level(avail: Int64, size: Int64, lowPercent: Int) -> SpaceLevel? {
        guard size > 0 else { return nil }
        let a = Double(avail) * 100, s = Double(size)
        if a < s * Double(criticalPercent) { return .critical }
        if a < s * Double(lowPercent) { return .low }
        return .ok
    }
}

/// smartmontools install failure, typed so the page model words it in the current language.
enum SmartInstallFailure: Equatable, Sendable { case exitCode(Int32), timedOut, noBrew }

struct ProtectedLocation: Equatable, Sendable {
    let relativePath: String
    let nameEN: String
    let nameRU: String
}

/// Home-relative locations macOS protects behind Full Disk Access, with the app each belongs to.
enum ProtectedLocations {
    static let table: [ProtectedLocation] = [
        ProtectedLocation(relativePath: "Library/Mail", nameEN: "Mail", nameRU: "Почта"),
        ProtectedLocation(relativePath: "Library/Messages", nameEN: "Messages", nameRU: "Сообщения"),
        ProtectedLocation(relativePath: "Library/Safari", nameEN: "Safari", nameRU: "Safari"),
        ProtectedLocation(relativePath: "Library/Application Support/AddressBook", nameEN: "Contacts", nameRU: "Контакты"),
        ProtectedLocation(relativePath: "Library/Calendars", nameEN: "Calendar", nameRU: "Календарь"),
        ProtectedLocation(relativePath: "Library/Group Containers/group.com.apple.notes", nameEN: "Notes", nameRU: "Заметки"),
        ProtectedLocation(relativePath: "Library/HomeKit", nameEN: "Home", nameRU: "Дом"),
    ]

    /// Table order; only `.denied` entries (missing and readable ones are dropped). `probe` gets the absolute path.
    static func denied(home: String, probe: (String) -> DirAccess) -> [ProtectedLocation] {
        table.filter { probe(home + "/" + $0.relativePath) == .denied }
    }
}

enum StorageTagKind: Equatable { case driveFailing, almostFull, driveWorn, lowSpace, ok, loading }

struct FreeableItem: Equatable {
    enum Kind: Equatable { case downloads, caches, trash }
    var kind: Kind
    var bytes: Int64
}

enum FolderRowAction: Equatable { case show(path: String), emptyTrash }

struct FolderRow: Equatable {
    var id: String
    var label: String
    var bytes: Int64
    var value: String
    var fraction: Double
    var action: FolderRowAction?
}

enum FoldersPhase: Equatable { case wait, list, failedEmpty(BlockFailure), failedWithList(BlockFailure) }

enum DriveState: Equatable { case ok, worn(Int), failing, noData, unavailable }

enum KVTone: Equatable { case plain, good, amber, hot, muted }

struct KVTile: Equatable {
    var label: String
    var value: String
    var tone: KVTone
}

enum StoragePageModel {
    // MARK: Page bar


    /// Priority: SMART failing, critical space, SMART worn, low space, OK.
    static func tag(space: SpaceLevel?, smartFailing: Bool, smartWorn: Bool) -> StorageTagKind {
        if smartFailing { return .driveFailing }
        if space == .critical { return .almostFull }
        if smartWorn { return .driveWorn }
        switch space {
        case .low: return .lowSpace
        case .ok: return .ok
        default: return .loading
        }
    }

    static func tagText(_ k: StorageTagKind) -> String {
        switch k {
        case .driveFailing: return L.storageTagDriveFailing
        case .almostFull: return L.storageTagAlmostFull
        case .driveWorn: return L.storageTagDriveWorn
        case .lowSpace: return L.storageTagLowSpace
        case .ok: return L.commonOK
        case .loading: return L.commonCollectingData
        }
    }

    static func sub(internalName: String?, size: Int64?) -> String {
        let name = internalName ?? L.reportCollectorInternalDiskFallbackTitle
        guard let size else { return name }
        return "\(name) · \(fmtCapacity(size))"
    }

    // MARK: Disk card

    static func heroNote(size: Int64, usedFraction: Double) -> String {
        L.storageHeroNote(fmtCapacity(size), L.homePercent("\(Int((usedFraction * 100).rounded()))"))
    }


    static let freeableMinBytes: Int64 = 100_000_000

    static func freeable(homeDirs: [DirSize]?, homeCaches: DirSize?, home: String) -> [FreeableItem] {
        var items: [FreeableItem] = []
        if let d = homeDirs?.first(where: { $0.path == home + "/Downloads" }) { items.append(FreeableItem(kind: .downloads, bytes: d.bytes)) }
        if let c = homeCaches { items.append(FreeableItem(kind: .caches, bytes: c.bytes)) }
        if let t = homeDirs?.first(where: { $0.path == home + "/.Trash" }) { items.append(FreeableItem(kind: .trash, bytes: t.bytes)) }
        return items.filter { $0.bytes >= freeableMinBytes }
    }

    static func itemName(_ k: FreeableItem.Kind) -> String {
        switch k {
        case .downloads: return L.storageDownloads
        case .caches: return L.storageCaches
        case .trash: return L.storageTrashLabel
        }
    }

    static func diskNote(level: SpaceLevel, lowPercent: Int, items: [FreeableItem]) -> String? {
        let list = items.map { L.storageFreeItem(itemName($0.kind), fmtCapacity($0.bytes)) }.joined(separator: ", ")
        let pctText = L.homePercent("\(lowPercent)")
        let critText = L.homePercent("\(StorageSpace.criticalPercent)")
        switch level {
        case .ok: return nil
        case .low: return items.isEmpty ? L.storageNoteLow(pctText) : L.storageNoteLowItems(pctText, list)
        case .critical: return items.isEmpty ? L.storageNoteCritical(critText) : L.storageNoteCriticalItems(critText, list)
        }
    }

    // MARK: Folders card



    static let homeTopCount = 8
    static let systemPaths = ["/Applications", "/Library", "/private/var", "/usr/local", "/opt/homebrew", "/Users/Shared"]

    /// Stable descending sort by bytes (ties keep input order).
    private static func sortedDesc<T>(_ xs: [T], bytes: (T) -> Int64) -> [T] {
        xs.enumerated().sorted { a, b in
            let x = bytes(a.element), y = bytes(b.element)
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
    }

    private static func finish(_ raw: [(id: String, label: String, bytes: Int64, action: FolderRowAction?)]) -> [FolderRow] {
        let top = raw.map(\.bytes).max() ?? 0
        return raw.map { FolderRow(id: $0.id, label: $0.label, bytes: $0.bytes, value: fmtCapacity($0.bytes),
                                   fraction: top > 0 ? Double($0.bytes) / Double(top) : 0, action: $0.action) }
    }

    static func homeRows(homeDirs: [DirSize], homeCaches: DirSize?, home: String, trashHidden: Bool) -> [FolderRow] {
        typealias Raw = (id: String, label: String, bytes: Int64, action: FolderRowAction?)
        let trashPath = home + "/.Trash"
        let top = sortedDesc(homeDirs.filter { $0.path != home && $0.path != trashPath && $0.bytes > 0 }, bytes: \.bytes)
            .prefix(homeTopCount)
        var raw: [Raw] = top.map { d in
            if d.path == home + "/Downloads" { return (d.path, L.storageDownloads, d.bytes, .show(path: d.path)) }
            return (d.path, "~/" + (d.path as NSString).lastPathComponent, d.bytes, nil)
        }
        if let c = homeCaches, c.bytes > 0 { raw.append((c.path, "~/Library/Caches", c.bytes, .show(path: c.path))) }
        if !trashHidden, let t = homeDirs.first(where: { $0.path == trashPath }), t.bytes > 0 {
            raw.append((t.path, L.storageTrashLabel, t.bytes, .emptyTrash))
        }
        return finish(sortedDesc(raw, bytes: { $0.bytes }))
    }

    static func systemRows(_ dirs: [DirSize]) -> [FolderRow] {
        finish(sortedDesc(dirs.filter { $0.bytes > 0 }, bytes: \.bytes).map { ($0.path, $0.path, $0.bytes, nil) })
    }


    /// A timed-out background recount over a visible list is ignored (D5); an empty result is not.
    static func foldersPhase(block: BlockPhase, hasCount: Bool) -> FoldersPhase {
        if hasCount {
            if case .failed(let f, _) = block, f == .noReading { return .failedWithList(.noReading) }
            return .list
        }
        switch block {
        case .loading: return .wait
        case .failed(let f, _): return .failedEmpty(f)
        case .ok: return .list
        }
    }

    static func foldersCaption(phase: FoldersPhase, counting: Bool, countedAt: Date?, now: Date, trashFreed: Int64?, someHidden: Bool) -> String {
        switch phase {
        case .wait: return L.storageCaptionCounting
        case .failedEmpty, .failedWithList: return L.storageCaptionCountFailed
        case .list: break
        }
        if counting { return L.storageCaptionCounting }
        if let freed = trashFreed { return L.storageCaptionTrashEmptied(fmtCapacity(freed)) }
        if someHidden { return L.storageCaptionSomeHidden }
        if let at = countedAt {
            let minutes = max(0, Int(now.timeIntervalSince(at) / 60))
            return L.storageCaptionCounted(minutes == 0 ? L.storageJustNow : L.storageAgo(minutes))
        }
        return L.storageCaptionTop
    }

    static func failureNote(_ f: BlockFailure) -> String {
        switch f {
        case .timedOut: return L.storageCountTimedOut
        case .noReading: return L.storageCountNoResult
        }
    }

    // MARK: Full Disk Access

    /// App names first (table order), then `~/<name>` of each unreadable home folder; duplicates removed.
    static func hiddenNames(denied: [ProtectedLocation], unreadableHome: [String], russian: Bool) -> [String] {
        var out: [String] = []
        for n in denied.map({ russian ? $0.nameRU : $0.nameEN }) + unreadableHome.map({ "~/" + ($0 as NSString).lastPathComponent }) where !out.contains(n) {
            out.append(n)
        }
        return out
    }

    static func fdaNote(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let first = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? L.storageFDANoteMore(first, names.count - 3) : L.storageFDANote(first)
    }

    // MARK: SMART


    static func driveState(_ d: SmartDisk, smartctlPresent: Bool) -> DriveState {
        guard let h = d.health else { return smartctlPresent ? .unavailable : .noData }
        if (h.criticalWarning ?? 0) != 0 || (h.mediaErrors ?? 0) > 0 { return .failing }
        if let pu = h.percentageUsed, pu >= 80 { return .worn(pu) }
        return .ok
    }

    static func driveSub(_ s: DriveState, isInternal: Bool) -> String {
        switch s {
        case .ok: return isInternal ? L.storageSubInternalOK : L.storageSubExternalOK
        case .noData, .unavailable: return isInternal ? L.storageSubInternalNoData : L.storageSubExternalNoData
        case .failing: return isInternal ? L.storageSubInternalFailing : L.storageSubExternalFailing
        case .worn(let p):
            let t = L.homePercent("\(p)")
            return isInternal ? L.storageSubInternalWorn(t) : L.storageSubExternalWorn(t)
        }
    }

    static func defaultSelection(_ disks: [SmartDisk], smartctlPresent: Bool) -> String? {
        let states = disks.map { ($0, driveState($0, smartctlPresent: smartctlPresent)) }
        if let f = states.first(where: { $0.1 == .failing }) { return f.0.device }
        if let u = states.first(where: { $0.0.device != "internal" && $0.1 == .unavailable }) { return u.0.device }
        if disks.contains(where: { $0.device == "internal" }) { return "internal" }
        return disks.first?.device
    }



    static let temperatureHighC = 70

    static func kvTiles(_ h: SmartHealth?) -> [KVTile] {
        func tile<T>(_ label: String, _ v: T?, _ fmt: (T) -> String, _ tone: (T) -> KVTone = { _ in .plain }) -> KVTile {
            guard let v else { return KVTile(label: label, value: "—", tone: .muted) }
            return KVTile(label: label, value: fmt(v), tone: tone(v))
        }
        let pct: (Int) -> String = { L.homePercent("\($0)") }
        let spareHot = h.flatMap { h in h.availableSpare.flatMap { s in h.spareThreshold.map { s < $0 } } } ?? false
        return [
            tile(L.storageKVTemp, h?.temperatureC, { L.storageCelsius($0) }, { $0 >= temperatureHighC ? .amber : .plain }),
            tile(L.storageKVUsed, h?.percentageUsed, pct, { $0 >= 100 ? .hot : ($0 >= 80 ? .amber : .plain) }),
            tile(L.storageKVSpare, h?.availableSpare, pct, { _ in spareHot ? .hot : .plain }),
            tile(L.storageKVSpareThreshold, h?.spareThreshold, pct),
            tile(L.storageKVHours, h?.powerOnHours, { fmtGrouped($0) }),
            tile(L.storageKVCycles, h?.powerCycles, { fmtGrouped($0) }),
            tile(L.storageKVUnsafe, h?.unsafeShutdowns, { fmtGrouped($0) }),
            tile(L.storageKVRead, h?.dataUnitsRead, { fmtTB(dataUnits: $0) }),
            tile(L.storageKVWritten, h?.dataUnitsWritten, { fmtTB(dataUnits: $0) }),
            tile(L.storageKVMediaErrors, h?.mediaErrors, { fmtGrouped($0) }, { $0 == 0 ? .good : .hot }),
            tile(L.storageKVErrorLog, h?.errorLogEntries, { fmtGrouped($0) }, { $0 == 0 ? .good : .plain }),
            tile(L.storageKVCritical, h?.criticalWarning, { $0 == 0 ? L.storageNo : L.storageYes }, { $0 == 0 ? .good : .hot }),
        ]
    }

    static func statusLine(_ s: DriveState) -> (text: String, hot: Bool)? {
        switch s {
        case .failing: return (L.storageStatusFailing, true)
        case .unavailable: return (L.storageStatusUnavailable, false)
        default: return nil
        }
    }

    static func wearNote(_ s: DriveState) -> String? {
        if case .worn(let p) = s { return L.storageWearNote(L.homePercent("\(p)")) }
        return nil
    }

    // MARK: Layout breakpoints (window width, never a measured child size)

    static let wideBreakpoint: CGFloat = 1150
    static func splitLeftWidth(wide: Bool) -> CGFloat { wide ? 240 : 200 }
    static func kvColumns(wide: Bool) -> Int { wide ? 3 : 2 }

    // MARK: smartmontools

    static func installFailureText(_ f: SmartInstallFailure) -> String {
        switch f {
        case .exitCode(let c): return L.storageInstallFailedCode(c)
        case .timedOut: return L.storageInstallTimedOut
        case .noBrew: return L.storageInstallNoBrew
        }
    }
}
