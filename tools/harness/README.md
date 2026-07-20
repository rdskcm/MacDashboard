# Headless UI render harness (reusable)

Renders app views offscreen with directly-injected `DashboardModel` state and
writes a PNG — no window, no interaction, no system mutation, no collectors.
Used to verify UI states that are hard to reach live (busy/error/progress states).

## Usage

1. Write a scenario file (anywhere, e.g. the session scratchpad — scenarios are
   throwaway; only the kit lives in the repo):

```swift
// scenario.swift
import AppKit
import SwiftUI

MainActor.assumeIsolated {
    L10nStore.shared.language = .ru          // pin language FIRST

    let m = DashboardModel()                  // init is side-effect-free; NEVER call start()
    m.report.brewVersion = .some(.some("Homebrew 4.x"))
    m.brewUpgrading = true                    // inject any state directly

    harnessRender(width: 460) {               // width per card column; omit `to:` —
        HarnessSection(label: "A: my state") {//   output path arrives as argv[1]
            MaintenanceCard(model: m)
        }
        // more HarnessSection(...) blocks stack vertically in one PNG
    }
}
```

2. Run: `tools/harness/render.sh scenario.swift /path/out.png`
3. Read the PNG to verify what actually rendered.

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
