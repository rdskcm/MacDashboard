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

- `--app`: default `dist.noindex/MacDashboard.app`; `--out`: default `tools/visual/out/<stamp>`; `--reference`: default `tools/visual/reference` (any dir of 1x PNGs named `<state>.png`).

**Main window height.** `1150 x H` pt, `H = min(780, screen_frame_h - 150)`,
refuses (exit 70) if `vw < 1260`, `H < 620` or `H > vh - 40`.

**Exit codes**: `0` all alpha ok, every diff ≤ threshold and no text change ·
`1` at least one alpha FAIL (wins over 2) · `2` no alpha FAIL but ≥1 state is
`CHANGED`, `SIZE-CHANGED`, `TEXT-CHANGED` or `NO-REF` (or its `text` column
reads `changed`) · `64` usage error · `65` precondition refused ·
`70` runtime error — restoration still ran. `--bless`/`--selftest` exit 0 on
success, 1 on refusal/failure.

## 3. Permissions

The **terminal running the tool** needs Screen Recording, Accessibility (AX
press, window geometry — no keystrokes are sent) and Automation → System
Events. A freshly built app's first launch can raise its own TCC prompts;
`assert_key` (before every AX action/capture) waits up to 30 s, printing
`waiting for MacDashboard to become key … — answer any system prompt`, and
on timeout names the state it was preparing and which of
frontmost/AXMain/bounds failed. The screen must be unlocked: a locked session shows no app windows, so the run refuses up front (exit 65) instead of failing to find the window.

## 4. States captured

**Real window (18 states, `screencapture -x -o -l <windowid>`):** `main`,
`main-report` (Report tab, via an AX press on the tab button — see §8),
`settings-general`, `settings-monitoring`, `settings-titlebar-hover`,
`settings-backup` (Backups section, third sidebar row), `main-iphone` (iPhone mode device list, fixture data),
`main-iphone-device` (the first tile opened via its AX identifier `iphone-tile-0`; the Back button is `iphone-back`),
`main-page-system` (Home's System tile opened via `home-tile-system`; the page's Back chip is `page-back`), each
`dark`/`light`. Window id via `vbtool windows --pid P`; the Settings window
must be 680±2 pt wide or the run aborts.

**Offscreen content (46 states, `tools/visual/content_states.swift` via
`tools/harness/render.sh`; `run.sh` aborts below 46):** `content-processes-{cpu,mem}`,
`content-folders-{home,service}`, `content-claude-backup` (the Claude backup
card), `content-history-{disk,battery,cycles,swap}`
(range Month), `content-home-{attention,sections}` (Home: attention card collapsed / expanded, All good, first scan, scan failed; section tiles normal / skeleton / last check / no battery; rendered with `animatesEntrance: false` because the offscreen host has no window and never fires `onAppear`), `content-history-disk-{quarter,year,all}`, `content-history-fresh` (the History section at 0, 1 and 2 recorded days and after a restart: notice + placeholder), and the iPhone cards
`content-iphone-{tiles,notices,battery,history,logs,import,identity,dialogs}`
(`history`: chart with the hover tooltip pinned, table, empty), each `dark`/`light`
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

`vbtool text-diff` reads the visible text of the reference and of the 1x
capture with Apple Vision (on-device `VNRecognizeTextRequest`; accurate,
language correction off, en-US, minimum text height 6 px). All whitespace is
removed from each line (Vision reads the same label as «3 d» or «3d» when
pixels elsewhere in the image change slightly), and the lines are compared as
multisets, ignoring order. A change that only adds or removes a space is
therefore not reported. Any line
on only one side sets the `text` column (9th in `results.tsv`) to `changed`;
a state whose pixel verdict was `same` becomes `TEXT-CHANGED` (exit 2). There
is no text threshold. Differing lines: `<run-dir>/text/<state>.txt`; every
state's summary line: `<run-dir>/text/summary.txt`; and the `text differences`
section of the report. The reference text is recognized afresh on every run —
no text is stored, so `--bless` is unchanged. Text the recognizer does not
read (very small or low-contrast glyphs, icons) is not covered; the
`ref_lines` count in `summary.txt` shows how much each state yielded.

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
domain is cleared for the run (snapshotted first, restored after). The fixture's Claude-backup status is a fixed last success 2 h before the fixture reference date (Jan 15, 2026 10:30 local); in fixture mode the backup age is measured from that reference date (`DashboardModel.fixtureNow`), so the Backups row, the card and its "2 h ago" are deterministic. The stale limit shown is the default 48 h (the card formats it as "2 d") because the defaults domain is cleared. Scroller style is pinned to overlay with the launch argument `-AppleShowScrollBars WhenScrolling` (argument domain, this process only), so a connected mouse or a "Show scroll bars" setting of Automatic/Always does not add a legacy scrollbar to `main-*`; the global setting is only read (recorded as `scrollbars:` in `build-info.txt`), never written.

Also snapshotted/restored: saved application state, App Support dir,
appearance, cursor, frontmost app. The App Support snapshot is taken with
a `ditto` copy with its ACLs stripped; the restore (`rsync -a --delete`) excludes every file whose
content is unchanged since the snapshot, so an unchanged file with a
protective ACL (the Time Machine history copy
`mac_check_state.timemachine-*.json` has `everyone deny write,delete`) is
never touched. Last line of every run: `RESTORE: app=…
defaults=… savedstate=… appsupport=…|partial(rsync_rc=N)
appearance=…|partial cursor=… front=… ls=…|partial`; an `rsync` failure on the appsupport
restore keeps `<run-dir>/restore-rsync.err`. A Settings window still open 5 s
after `close_settings` aborts the run loudly.

**Cannot be undone:** TCC prompts. The LaunchServices registration of the built app bundle is undone at exit by `tools/ls-prune.sh` (`ls=ok`), or `ls=partial` if ls-prune failed, timed out, or left a still-running copy registered; a SIGKILLed run leaves it until the next build. If SIGKILLed (no trap runs), the pre-run backup stays in
`<run-dir>/.restore/` — restore by hand (`defaults import` the plist, `rsync
-a --delete` `appsupport/` back over the App Support dir), skipping any step
marked absent. A by-hand `rsync -a --delete` reports `Permission denied` for an ACL-protected
file; that is harmless when `cmp` shows the file equal to its backup copy.

## 8. Driving routes

**Main tab / Settings open/close.** AX press only, no keystrokes (intermittent
here). `press_main_tab` matches `AXIdentifier` (`main-report` — the header Report button, which
toggles the report — `home-tile-*`, `page-back`, `.accessibilityIdentifier` — `.accessibilityLabel` lands in
AXAttributedDescription, unreadable here); `open_settings`/`close_settings`
match name/menu item/subrole; all three abort and report what they saw if
not found — never a coordinate click.

**Sidebar.** `press_section <label>` is the one **coordinate-click
contingency**: the Settings sidebar `List` is not AX-exposed here at all
(unlike the main tab control). It clicks `(x+98, y+T+29)`/`(x+98, y+T+65)`/`(x+98, y+T+101)` (General/Monitoring/Backup)
from the Settings window's bounds and titlebar height `T = h - 420`. A
Monitoring-vs-Backup sanity guard aborts the run if the Backup click changed nothing.
