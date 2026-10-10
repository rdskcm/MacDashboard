# Headless UI render harness (reusable)

Renders app views offscreen with directly-injected `DashboardModel` state and
writes a PNG — no window, no interaction, no system mutation, no collectors.
Used to verify UI states that are hard to reach live (busy/error/progress states).

## Usage

1. Write a scenario file (anywhere, e.g. the session scratchpad — most scenarios are
   throwaway; a few worth re-running are kept in the repo next to the kit, e.g.
   `scenario_ds_specimen.swift` and `scenario_smart_install.swift`):

```swift
// scenario.swift
import AppKit
import SwiftUI

MainActor.assumeIsolated {
    L10nStore.shared.language = .ru          // pin language FIRST

    let m = DashboardModel()                  // init is side-effect-free; NEVER call start()
    m.report.brewStatus = .installed(version: "Homebrew 4.x")
    m.brewUpgrading = true                    // inject any state directly

    harnessRender(width: 460) {               // width per card column; omit `to:` —
        HarnessSection(label: "A: my state") {//   output path arrives as argv[1]
            MaintenanceCard(model: m)
        }
        // more HarnessSection(...) blocks stack vertically in one PNG
    }
}
```

2. Run: `tools/harness/render.sh scenario.swift /path/out.png [light|dark|both]` — see Themes below.
3. Read the PNG to verify what actually rendered.

## Themes (light / dark)

A render is **unpinned** by default: it uses whatever theme the Mac is in, so the
same command checks a different theme on a different day. Pin it:

- `render.sh scenario.swift /path/out.png both` → compiles once, writes
  `/path/out-light.png` and `/path/out-dark.png`. `light` or `dark` instead of
  `both` → one PNG at `/path/out.png` in that theme.
- In code: `harnessRender(width: 460, appearance: .light) { … }` pins that call
  whatever the mode argument says (explicit argument wins). Use it only for a
  state that exists in one theme; otherwise leave it out so `both` works.
- Every render prints `  appearance: <light|dark> (<pinned|unpinned>)` under
  its `Wrote …` line — check it before trusting a PNG.
- `both` derives file names from the output path. A scenario that writes to its
  own `to:` paths would get the same path twice (dark overwrites light): give
  such a scenario `appearance:` per call and a per-theme path instead.
- Light-theme review (hard rule): text roles use the `-ink` colors — accent-ink
  `#1A63C2`, green-ink `#0A7454`, amber-ink `#8C5C00`, muted `#5E6774`; fills,
  dots, borders and strokes keep the base colors. Check the `-light.png`.

## Rules & gotchas (empirical — don't relearn)

- Scenario is compiled as `main.swift` (render.sh copies it) — top-level
  statements are only legal under that exact filename.
- Everything app-side is `@MainActor` → wrap the scenario body in
  `MainActor.assumeIsolated { ... }`.
- Never call model methods that spawn work (`start()`, `upgradeBrewNow()`,
  `refreshReport()`, …) — inject fields instead.
- Do not link `-framework Observation` (render.sh already knows).
- Injected `Assessment`/`Tip` etc. work fine: build the value, assign to
  `model.assessment`.
- Sections render at 2x on Retina; PNG height grows with content — keep a
  scenario to ~4 sections so the image stays readable.
- `NavigationSplitView` sidebars render as an EMPTY white panel offscreen (the
  List needs a real window/appearance context) — the detail pane renders fine.
  Verify sidebars in the real app (System Events menu click + screencapture).
- **Layout-and-appearance verifier, not a rendering verifier.** The PNG comes from
  `cacheDisplay(in:to:)`: the views draw straight into a bitmap — no window, no
  window server, no Core Animation compositing. Geometry, text, colors and which
  state shows what are trustworthy; anything that exists only when layers are
  composited on screen (content escaping its row during scroll or animation,
  material/translucency blending, between-frame artefacts) never appears here,
  so a clean PNG is no evidence against it (the row-escape defect was in this
  class). Same root cause as the blank sidebar above. Verify that class in the
  real app: `tools/visual/run.sh` or a live screencapture.
- Window chrome (titlebar, translucency, traffic lights, alpha holes) is invisible here — use `tools/visual/run.sh` (real windows, reference diff).
