// tools/harness/scenario_ds_specimen.swift
// Block V2-FOUND design-system specimen: card surface, recessed track, sliding
// segmented control (both states), disclosure bars (both states), full DS
// colour swatch row, kicker label. Appearance forced via DS_APPEARANCE env var
// ("dark" | "light", default "light") read before any DS color is evaluated.

import AppKit
import SwiftUI

MainActor.assumeIsolated {
    let wantDark = ProcessInfo.processInfo.environment["DS_APPEARANCE"] == "dark"
    NSApplication.shared.appearance = NSAppearance(named: wantDark ? .darkAqua : .aqua)

    let swatches: [(String, Color)] = [
        ("ground", DS.ground), ("ground2", DS.ground2), ("ink", DS.ink), ("inkSoft", DS.inkSoft),
        ("muted", DS.muted), ("line", DS.line), ("lineStrong", DS.lineStrong), ("track", DS.track),
        ("row", DS.row), ("accent", DS.accent), ("accentInk", DS.accentInk), ("green", DS.green),
        ("greenInk", DS.greenInk), ("amber", DS.amber), ("amberInk", DS.amberInk), ("hot", DS.hot),
        ("violet", DS.violet), ("glass3", DS.glass3),
    ]

    harnessRender(width: 820) {
        VStack(alignment: .leading, spacing: 24) {
            Text("Specimen").dsKicker()

            VStack(alignment: .leading, spacing: 8) {
                Text("Card surface").font(.headline).foregroundStyle(DS.ink)
                Text("Sample body content on .regularMaterial.").font(.caption).foregroundStyle(DS.inkSoft)
            }
            .padding(16)
            .dsCardSurface()

            dsRecessedTrack(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(width: 300, height: 28)

            DSSlidingSegmented(options: ["A", "B"], selection: .constant("A")) { $0 }
                .frame(width: 220)
            DSSlidingSegmented(options: ["A", "B"], selection: .constant("B")) { $0 }
                .frame(width: 220)

            HStack(spacing: 24) {
                VStack { DSDisclosureBars(expanded: false); Text("collapsed").font(.caption2).foregroundStyle(DS.muted) }
                VStack { DSDisclosureBars(expanded: true); Text("expanded").font(.caption2).foregroundStyle(DS.muted) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("DS palette").dsKicker()
                HStack(spacing: 10) {
                    ForEach(swatches, id: \.0) { name, color in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 28, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.line, lineWidth: 1))
                            Text(name).font(.system(size: 8)).foregroundStyle(DS.inkSoft)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(DS.ground)
    }
}
