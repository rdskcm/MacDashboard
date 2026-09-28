# Visual baseline (`tools/visual/`)

## 1. Purpose

`tools/harness/` renders SwiftUI views offscreen — no window, no chrome, so
it cannot see anything that depends on the real NSWindow: titlebar,
translucency, traffic lights, or an alpha-0 hole in the window background
(the defect this tool was built to catch, see `VisualEffectBackground.swift`).
`tools/visual/` captures the app's real windows with `screencapture`, renders
below-the-fold cards offscreen from the same fixed dataset, checks each
real-window capture for alpha holes, and diffs every state against a
reference.

## 2. Usage

```
tools/visual/run.sh [--app PATH] [--out DIR] [--reference DIR] [--allow-old-sdk]
tools/visual/run.sh --bless RUN_DIR [STATE ...]
tools/visual/run.sh --selftest
tools/visual/run.sh -h | --help
```

Typical run: `./build_app.sh && tools/visual/run.sh`, about 1–2 minutes. It
moves the real cursor and sends AX actions (no synthetic keystrokes) — do not
use the Mac while it runs.

- `--app`: default `dist/MacDashboard.app`; `--out`: default `tools/visual/out/<stamp>`; `--reference`: default `tools/visual/reference` (any dir of 1x PNGs named `<state>.png`).

**Main window height.** `1150 x H` pt, `H = min(780, screen_frame_h - 150)`,
refuses (exit 70) if `vw < 1260`, `H < 620` or `H > vh - 40`.

**Exit codes**: `0` all alpha ok and every diff ≤ threshold · `1` at least
one alpha FAIL (wins over 2) · `2` no alpha FAIL but ≥1 state is `CHANGED`,
`SIZE-CHANGED` or `NO-REF` · `64` usage error · `65` precondition refused ·
`70` runtime error — restoration still ran. `--bless`/`--selftest` exit 0 on
success, 1 on refusal/failure.

## 3. Permissions

The **terminal running the tool** needs Screen Recording, Accessibility (AX
press, window geometry — no keystrokes are sent) and Automation → System
Events. A freshly built app's first launch can raise its own TCC prompts;
`assert_key` (before every AX action/capture) waits up to 30 s, printing
`waiting for MacDashboard to become key … — answer any system prompt`, and
on timeout names the state it was preparing and which of
frontmost/AXMain/bounds failed.

## 4. States captured

**Real window (10 states, `screencapture -x -o -l <windowid>`):** `main`,
`main-report` (Report tab, via an AX press on the tab button — see §8),
`settings-general`, `settings-monitoring`, `settings-titlebar-hover`, each
`dark`/`light`. Window id via `vbtool windows --pid P`; the Settings window
must be 680±2 pt wide or the run aborts.

**Offscreen content (22 states, `tools/visual/content_states.swift` via
`tools/harness/render.sh`):** `content-processes-{cpu,mem}`,
`content-folders-{home,service}`, `content-history-{disk,battery,cycles,swap}`
(range Month), `content-history-disk-{quarter,year,all}`, each `dark`/`light`
— cards below the fold of the real window, which would need fragile
scroll/click driving to reach there.

## 5. The alpha check and comparison

The alpha check proves no pixel inside a real window's own shape is fully
transparent — a `.clear` NSWindow background relying on SwiftUI content to
paint every pixel can leave a strip unpainted: click-through, see-through to
the desktop. Parameters: `corner_pt=32`, `edge_inset_px=0`. Offscreen
`content-*` states have no window shape, so their `alpha` column reads `n/a`
and `hole_px`/`bbox_pt`/`regions` read `0`/`-`/`-`.

`vbtool diff`: a pixel differs when the max over R/G/B/A of `|ref − cur|`
exceeds `pixel_tolerance` (24, `thresholds.txt`). A state is `CHANGED` when
`diff_pct` exceeds its threshold (`default 0.5`, per-state overrides and the
noise measurement behind them live in `thresholds.txt`, not duplicated here).

## 6. References

Live in `tools/visual/reference/` as 1x PNGs (`<state>.png`) plus
`manifest.txt` (`state blessed_date macos sdk commit` per line). **Refreshed
only after a human has seen the contact sheet and accepted the change**, via
`run.sh --bless <run-dir> [states]`, committed on the block's branch.
`--bless` refuses an overridden SDK gate and any non-`content-*` state whose
`alpha` is not `ok` (`content-*` also accepts `n/a`). The report's provenance
section compares each state's manifest macOS/SDK against the current run's.

## 7. Fixture mode, what the tool restores, diagnostics

The app is launched with `-visualFixture 1`: it shows a fixed, built-in
dataset (`VisualFixture.swift`) instead of live data, so `main-*`,
`main-report-*` and every `content-*` state are deterministic regardless of
live machine state (wake holders, battery, history); the app's `defaults`
domain is cleared for the run (snapshotted first, restored after).

Also snapshotted/restored: saved application state, App Support dir,
appearance, cursor, frontmost app. Last line of every run: `RESTORE: app=…
defaults=… savedstate=… appsupport=…|partial(rsync_rc=N)
appearance=…|partial cursor=… front=…`; an `rsync` failure on the appsupport
restore keeps `<run-dir>/restore-rsync.err`. A Settings window still open 5 s
after `close_settings` aborts the run loudly.

**Cannot be undone:** TCC prompts; LaunchServices registration of the built
app bundle. If SIGKILLed (no trap runs), the pre-run backup stays in
`<run-dir>/.restore/` — restore by hand (`defaults import` the plist, `rsync
-a --delete` `appsupport/` back over the App Support dir), skipping any step
marked absent.

## 8. Driving routes

**Main tab / Settings open/close.** AX press only, no keystrokes (intermittent
here). `press_main_tab` matches `AXIdentifier` (`main-tab-overview`/
`main-tab-report`, `.accessibilityIdentifier` — `.accessibilityLabel` lands in
AXAttributedDescription, unreadable here); `open_settings`/`close_settings`
match name/menu item/subrole; all three abort and report what they saw if
not found — never a coordinate click.

**Sidebar.** `press_section <label>` is the one **coordinate-click
contingency**: the Settings sidebar `List` is not AX-exposed here at all
(unlike the main tab control). It clicks `(x+98, y+T+29)`/`(x+98, y+T+65)`
from the Settings window's bounds and titlebar height `T = h - 420`.
