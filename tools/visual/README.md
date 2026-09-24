# Visual baseline (`tools/visual/`)

## 1. Purpose

`tools/harness/` renders SwiftUI views offscreen — no window, no chrome, so
it cannot see anything that depends on the real NSWindow: the system
titlebar, translucency, traffic lights, or an alpha-0 hole in the window
background (the defect this tool was built to catch, see
`VisualEffectBackground.swift`). `tools/visual/` captures the app's real
windows with `screencapture`, checks each for alpha holes, and diffs it
against a stored reference.

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

- `--app`: default `dist/MacDashboard.app` (the `./build_app.sh` output).
- `--out`: default `tools/visual/out/<YYYYmmdd-HHMMSS>`.
- `--reference`: default `tools/visual/reference`; can point at any directory
  of 1x PNGs named `<state>.png`, e.g. an earlier run's `norm/` for a noise
  or before/after comparison.

**Main window height.** `1150 x H` pt, `H = min(780, screen_frame_h - 150)`
(`screen_frame_h` = the full `NSScreen.main` frame height, i.e. the `H` field
of `vbtool screen`); refuses (exit 70) if `vw < 1260`, `H < 620` or
`H > vh - 40` (`vh` = the screen's visible frame height). Recorded as
`main_window_pt: 1150xH` in `build-info.txt`. `vh` (the visible frame height)
has been observed to drift by 1–2 pt between runs on the same, unchanged
screen (menu bar / Dock layout jitter); `H` is derived from the full screen
frame height instead, which is stable, so it no longer produces a false
`SIZE-CHANGED` from that drift alone.

**Exit codes**: `0` all alpha ok and every diff ≤ threshold · `1` at least
one alpha FAIL (wins over 2) · `2` no alpha FAIL but ≥1 state is `CHANGED`,
`SIZE-CHANGED` or `NO-REF` · `64` usage error · `65` precondition refused,
nothing changed · `70` runtime error — the run aborted, restoration still
ran. `--bless`/`--selftest` exit 0 on success, 1 on refusal/failure.

## 3. Permissions

The **terminal running the tool** needs Screen Recording
(`CGPreflightScreenCaptureAccess`, for `screencapture`), Accessibility (AX
press, window geometry — no keystrokes are sent), and Automation → System
Events. A freshly built, ad-hoc-signed app's first launch can raise its own
TCC prompts (folder access, System Events); `assert_key` (before every AX
action and capture) waits up to 30 s, printing `waiting for MacDashboard to
become key (front app: <name>) — answer any system prompt`.

## 4. States captured

8 states, `screencapture -x -o -l <windowid>` on the app's key window:
`main`, `settings-general`, `settings-monitoring`, `settings-titlebar-hover`,
each in `dark` and `light`.

**Window id.** `vbtool windows --pid P` calls `CGWindowListCopyWindowInfo`
(`[.optionOnScreenOnly, .excludeDesktopElements]`), keeps entries with
`kCGWindowOwnerPID == P`, `kCGWindowLayer == 0`, `kCGWindowAlpha > 0`, prints
`id x y w h` (top-left global points) per window, front to back. The main
window is the single such window right after launch. The Settings window is
the one that appears after opening Settings (see §9) whose id differs from
the main window's; it must be 680±2 pt wide (SwiftUI root `.frame(width:
680, height: 420)`) or the run aborts.

## 5. The alpha check

Proves no pixel inside the window's own shape (as opposed to its
rounded-corner cutout) is fully transparent — a `.clear` NSWindow background
relying on SwiftUI content to paint every pixel can leave a strip unpainted:
click-through, see-through to the desktop. Parameters: `corner_pt=32`
(corner-flap radius, excluded to allow any rounded-corner radius up to
32 pt), `edge_inset_px=0` (raise only when a `main-*` row shows holes
confined to the outermost 1 px ring, evidence recorded here — not yet
observed).

## 6. Comparison

`vbtool diff`: a pixel differs when the max over R/G/B/A of `|ref − cur|`
exceeds `pixel_tolerance` (24, `thresholds.txt`). A state is `CHANGED` when
`diff_pct` exceeds its threshold (`default 0.5`, with per-state overrides).

**Run-to-run noise, measured 2026-09-24** (macOS 27.0, this bench Mac,
1280x741 pt visible frame, 1150x682 pt window, two consecutive positive runs
at the same `H`): `main-dark` 0.92 %, `main-light` 0.59 %, all `settings-*`
0.00 %. By the `thresholds.txt` rule (`max(1.0, 2 × max observed main-* pct)`,
rounded up to 0.5), `main-dark`/`main-light` are set to 2.0 % there; every
other state keeps `default` (0.5 %).

## 7. References

Live in `tools/visual/reference/` as 1x PNGs (`<state>.png`) plus
`manifest.txt` (`state blessed_date macos sdk commit` per line). **Refreshed
only after a human has seen the contact sheet and accepted the visual
change**, via `run.sh --bless <run-dir> [states]`, committed on the block's
branch. `--bless` refuses a run whose SDK gate was overridden
(`sdk_gate: overridden`) and any state whose `alpha` column is not `ok`.
Never bless a run just to make it exit 0 — blessing changes what "same"
means for every future run.

## 8. What the tool restores

Snapshotted before any change, restored on normal exit, on error and on
Ctrl-C/SIGTERM: the `defaults` domain `com.rdskcm.mac-dashboard`,
`~/Library/Saved Application State/com.rdskcm.mac-dashboard.savedState`,
`~/Library/Application Support/MacDashboard/`, system appearance (Dark/Light
+ Auto flag), the cursor position, the frontmost app. The launched app
instance is quit. Last line of every run:
`RESTORE: app=… defaults=… savedstate=… appsupport=… appearance=…|partial cursor=… front=…`.

**Cannot be undone:** TCC decisions made at prompts during a run (the user's
own grants, not run state); LaunchServices registration of the built,
ad-hoc-signed app bundle.

If SIGKILLed (no trap runs), the pre-run backup stays in
`<run-dir>/.restore/` — restore by hand, skipping any step whose source is
marked absent, then check System Settings → Appearance manually:
```
defaults delete com.rdskcm.mac-dashboard
defaults import com.rdskcm.mac-dashboard <run-dir>/.restore/defaults.plist
rm -rf ~/Library/Saved\ Application\ State/com.rdskcm.mac-dashboard.savedState
ditto <run-dir>/.restore/savedState ~/Library/Saved\ Application\ State/com.rdskcm.mac-dashboard.savedState
rsync -a --delete <run-dir>/.restore/appsupport/ ~/Library/Application\ Support/MacDashboard/
```

## 9. Driving routes

**Settings open/close.** AX press only, no keystrokes: Cmd+, / Cmd+W proved
intermittent on this bench (a keystroke goes to whatever holds keyboard focus
at delivery; an AX press does not). `open_settings` finds, in menu bar item 2
(the application menu), the first menu item whose name starts with "Settings"
and performs `AXPress`; if none is found it reports the menu items it saw and
aborts (never falls back to keystrokes). `close_settings` finds the process
window matching the Settings window's last bounds (±1 pt) and presses the
button with `subrole` `AXCloseButton`.

**Sidebar.** `press_section <label>` uses the **coordinate-click
contingency**, not an AX press: the sidebar `List` is not exposed to System
Events on this macOS (`entire contents of window 1` returns only the
traffic-light buttons and the detail-pane controls), though it is visible and
mouse-clickable. It clicks `(x+98, y+T+29)` for General and `(x+98, y+T+65)`
for Monitoring, from the Settings window's bounds `(x, y)` and titlebar
height `T = h - 420` — the fallback coordinates given in the block spec.
