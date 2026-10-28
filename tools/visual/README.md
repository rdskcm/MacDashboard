# Visual checks (`tools/visual/`)

## 1. Overview

Two tools, run in this order for a GUI block:

| tool | what it covers | Mac usable meanwhile |
|---|---|---|
| `snapshots.sh` | every screen part that renders offscreen, dark and light, inside `swift test` | yes |
| `smoke.sh` | the three things only a real window shows: Home with the glass looks, the Report, the Settings window | no (about 2 min) |

`tools/harness/` stays the ad-hoc scenario tool; it is not a verification stage.

## 2. Offscreen snapshots (`tools/visual/snapshots.sh`)

Every screen part that renders offscreen is drawn inside `swift test`, dark and light, and compared with a reference picture. No window opens, so the Mac can be used during the run. The states are the `run.snap` calls in `Tests/MacDashboardTests/ContentSnapshotTests.swift`. The pictures are window-server captures of windows that are never shown (`screencapture -l`), so the terminal running the tool needs Screen Recording permission; without it the run stops at the first state and exits 70 with a message saying so.

- Run: `tools/visual/snapshots.sh [--out DIR]`. About 1.5 min on a warm build (rendering ~80 s of it; the comparison runs in `vbtool snap-compare`, built with `-O`, ~5 s; `timing.txt` in the run directory shows the split). The run directory (`tools/visual/out/snap-<time>/`) holds `results.tsv`, `rendered.tsv` (what the test rendered), `timing.txt`, `current/` (the new PNGs), `diff/` (masks of changed pixels), `build-info.txt` and, when anything differs, `contact-sheet.png` (before / after / difference).
- Exit codes: 0 every state same; 2 any CHANGED, SIZE-CHANGED, NO-REF or ORPHAN-REF; usage, main display not 2x (references are 2x bitmaps) and build/test/runtime errors have their own codes, listed in the header of the script.
- References live in `Tests/Snapshots/<state>.png`, with `manifest.txt` next to them. They change only through `tools/visual/snapshots.sh --bless <run dir> [state ...]` after a person has looked at the contact sheet. Without state names `--bless` takes every row that is not `same`; a reference whose state no longer exists (ORPHAN-REF) is deleted by `--bless`.
- Diff rule: a pixel is changed when any channel differs by more than 24; no changed pixel is allowed. Offscreen rendering on one Mac is deterministic, so a state that differs between two runs is a defect to fix at its source, never a reason to add tolerance.
- Bench home: the test process runs with `CFFIXED_USER_HOME=tools/visual/out/snapshot-home` (emptied each run) and refuses to run when its home is the real home. It never reads the app's real data. `MACDASH_SNAPSHOTS` (set by the script) enables the suite; a plain `swift test` and CI skip it.

## 3. Real-window smoke run (`tools/visual/smoke.sh`)

```
tools/visual/smoke.sh [--app PATH] [--out DIR] [--reference DIR] [--allow-old-sdk]
tools/visual/smoke.sh --bless RUN_DIR [STATE ...]
tools/visual/smoke.sh --selftest
tools/visual/smoke.sh -h | --help
```

Typical run: `./build_app.sh && tools/visual/smoke.sh`, about 2 minutes. It moves the real cursor and sends AX actions (no synthetic keystrokes): **do not use the Mac while it runs.**

**Bench copy.** `tools/bench-app.sh` copies the build to `<run dir>/app/MacDashboard.app` under the bundle id `com.rdskcm.mac-dashboard.bench` (ad-hoc re-signed with the app's entitlements). The copy runs with `CFFIXED_USER_HOME=<run dir>/home` (empty), `-ApplePersistenceIgnoreState YES`, `-appLanguage en`, `-AppleShowScrollBars WhenScrolling` and `-visualFixture 1`. The run never reads or writes the real defaults domain, its saved state, the system appearance or the App Support folder. The only state it creates is the bench defaults domain and the bench saved-state folder, both removed at exit (a killed run leaves them; the next run deletes them at launch).

**Dark / light** is switched inside the app: under `-visualFixture` the app follows the fixture-only key `visualAppearance` (`dark` / `light`) in its own defaults domain, observed by KVO (`FixtureAppearance.swift`). The system setting is never touched.

**States (14, `STATE_ORDER` in the script):** `main`, `main-glass-clear`, `main-glass-tinted`, `main-glass-rt`, `main-report`, `settings-general`, `settings-glass-rt`, each `-dark` and `-light`. Window id via `vbtool windows --pid P`; the Settings window must be 680 +/- 2 pt wide. The script aborts if the number of captured states differs from `STATE_ORDER`.

**Glass looks.** `main-glass-clear` / `main-glass-tinted` set the fixture-only key `visualGlassTintAmount` (0 / 1) and `main-glass-rt` / `settings-glass-rt` set `visualReduceTransparency` in the bench domain before the capture; the app follows them live by KVO (`Engine/GlassTint.swift`) and the keys are deleted after each group. The cards, the header bar and the Settings cards follow these keys; the system Liquid Glass slider and Reduce Transparency are never touched.

**Routes.** All by accessibility identifier, never a coordinate click: `press_main_tab main-report` (the header Report button), `press_main_tab report-done` (the sheet's Done button), `open_settings` (app-menu item whose name starts with "Settings"), `close_settings` (the `AXCloseButton`).

**Report open / close.** The Report is a sheet, opened with one press of `main-report`; the run waits up to 5 s for the identifier `report-sheet` and for a second window of the pid. It is captured as the main window's screen region (the sheet is a separate window, so a window-id capture would miss it) and closed with one press of `report-done`; the run waits up to 5 s for `report-sheet` to be gone. On a timeout the run stops with a runtime error naming the state; it never presses a second time.

**Alpha check.** No pixel inside a window's own shape may be fully transparent (parameters `corner_pt=32`, `edge_inset_px=0`).

**Comparison.** `vbtool diff`: a pixel differs when the max over R/G/B/A of `|ref - cur|` exceeds `pixel_tolerance` (`thresholds.txt`); a state is `CHANGED` when `diff_pct` exceeds its threshold. `vbtool text-diff` also compares the visible text of reference and capture with Apple Vision (whitespace removed, lines compared as multisets); a changed line makes a pixel-`same` state `TEXT-CHANGED`. Two guards abort the run: `main-dark` vs `main-light` must differ by more than 5 % (proves the in-app appearance switch), and `main-report-dark` vs `main-dark` by more than 1 %.

**Exit codes**: 0 all alpha ok, every diff within its threshold and no text change; 1 at least one alpha FAIL; 2 no alpha FAIL but a state is `CHANGED`, `SIZE-CHANGED`, `TEXT-CHANGED`, `NO-REF` or `ORPHAN-REF`. Precondition refusals, usage errors and runtime errors have their own codes (see `-h`). Preconditions: screen unlocked, no MacDashboard process running (a window behind the bench window would change the glass backdrop), SDK not older than the macOS major, Screen Recording, Accessibility, `cliclick`.

**References** live in `tools/visual/reference/<state>.png` (1x) with `manifest.txt`. They change only through `smoke.sh --bless <run dir> [states]` after a person has looked at the contact sheet. `--bless` refuses an overridden SDK gate and any state whose `alpha` is not `ok`. A reference file whose state is not in `STATE_ORDER` is reported as ORPHAN-REF (exit 2); `--bless` of it deletes the file. The report's provenance section compares each state's manifest macOS/SDK with the current run.

**Permissions.** The terminal running the tool needs Screen Recording, Accessibility and Automation to System Events. A freshly built app's first launch can raise TCC prompts; `assert_key` waits up to 30 s before every capture and names the failing condition on timeout.
