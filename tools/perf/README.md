# Perf gate (`tools/perf/`)

## 1. Purpose

`tools/perf/gate.sh` measures the main-thread, Core Animation and WindowServer cost of the real app
(scenarios G1-G7, G9, G10 and GP:<page>; G8, the System page's breathing Outdated capsule, was retired in PERF-GATE-RETARGET because REDESIGN-SYSTEM removed that capsule) and compares it with absolute limits and, optionally, with a pre-block build. It
exists because per-frame animation work cannot be seen by the offscreen harness or the visual baseline
(rule `gpu-per-frame`). It runs nightly (`night.sh`) and at release prep; per block only when the queue row says perf: yes.

## 2. Usage

```
tools/perf/gate.sh [--app PATH] [--baseline PATH] [--scenarios LIST] [--runs N] [--out DIR]
                   [--keep-traces] [--g1-max PCT]
tools/perf/gate.sh -h
```

Typical run, on AC power with Low Power Mode off, about 8 minutes per scenario (3 runs x 2 arms x ~75 s), **do not use the Mac while it runs**
(it moves the real pointer and sends AX actions):

```
cd MacDashboard && ./build_app.sh && tools/perf/gate.sh --baseline tools/perf/out/baseline.noindex/MacDashboard.app
```

- `--app` default `dist.noindex/MacDashboard.app`. `--baseline`: candidate and baseline runs alternate A,B,A,B so drift hits both.
- Baseline rule: the `--baseline` bundle must be built from the PERF-GATE-RETARGET merge or later, the first build with the `report-show-in-finder` identifier (G5 route). An older baseline can lack an element a route needs; that run is an ERROR on the baseline arm (tag `<item>-base<N>`, the report adds a baseline hint) and the scenario gets no verdict: rebuild the baseline from a newer commit. The night runner's baseline (its previous build) meets the rule.
- `--scenarios`: `G1..G7`, `G9`, `G10` (live-resize sweep, RESIZE-MOTION), `GP:<page>` (scroll scenario on one page: cpu memory storage battery security backups system history) or `all` (every G item plus GP for all pages); default `G1,G2,G3,G4,G5,G6,G7,G9` (G10 is not in the default list; `all` includes it). `--runs` 1-7, default 3 for every item; arms are aggregated by median.
- Both bundles are copied with `tools/bench-app.sh` (bundle id `com.rdskcm.mac-dashboard.bench`) into `$OUT/apps`, removed at exit; the app runs with `-appLanguage en -ApplePersistenceIgnoreState YES`.
- `--out` must be inside `tools/perf/out/` (gitignored); default `tools/perf/out/<stamp>`. A reused `--out` keeps the previous `summary`/`report`/`runs` files under a time-stamped name.
- `--keep-traces` keeps the `.trace` bundles and exported XML (10-60 MB each). `*-analysis.txt` is always kept.
- `--g1-max` is the absolute G1 app CPU limit: 5.6 (the level before C7), 2.5 after the process-list fix.

Outputs in the run directory: `summary.tsv` (`scenario arm run metric value threshold verdict`),
`report.md` (one table per scenario, power log, ERROR scenarios, defaults verdict), `power.log`, `*-analysis.txt`,
`errors.tsv` (`scenario tag reason diagnostics`, one line per ERROR run; diagnostics is `<tag>-axdiag/` for an AX miss —
AX identifier dump with frames, `drv winfo`, screenshot, display state — or the run's log for a trace or analysis failure:
`<tag>-rec.txt`, `<tag>-export.err`, `<tag>-analysis.txt` or `<tag>-drv.txt`) and `error-runs.tsv` (runs of ERROR scenarios, no verdict),
and the last stdout line `GATE: exit=<n> pass=<k> fail=<m> noisy=<j> invalid=<0|1> error=<e>`.

## 3. Exit codes

`0` pass (NOISY rows do not fail) · `1` any FAIL (absolute or regression rule) · `3` INVALID run: the power check after a run (or a `Using Batt`
entry in `pmset -g log` during it) failed twice; the numbers are discarded, never averaged · `4` the defaults domain
`com.rdskcm.mac-dashboard` differs before/after (the gate runs bench copies and never writes that domain, so 4 means another process changed it; the diff is printed) · `5` ERROR: at least one scenario was not measured, because an AX element (press, frame, wait or scroll probe) was still missing after one retry, or one run's trace or analysis failed (no trace, export failed, analyze.py failed, scenario marks missing); the other scenarios ran and are reported · `64` usage ·
`65` precondition refused · `70` runtime error before or around a run (cannot create the run directory, bench copy or helper build failed, the fixture could not be built, the app exited at launch, the window could not be pinned, the final verdict step failed).
When several apply: 3 over 4 over 5 over 1. An AX miss is retried once after the app is brought to the front (for a
Home tile after a fresh `main-mode-mac` press); this retry is robustness, not a fix: the first night's 6-of-8 Home
tile AX tree has no known cause yet. A second miss writes `<tag>-axdiag/`, stops that app, marks the scenario ERROR
and the gate continues with the next scenario. A trace or analysis failure is not retried: the run is ERROR at once, with the log named in errors.tsv. There is never a coordinate fallback.

Preconditions (65): AC power and Low Power Mode 0 · screen unlocked · main display at least 1280x800 pt · Accessibility
enabled · `xcrun xctrace version` works · no other `gate.sh` running · bench home not inside `~/Library`.

## 4. Scenarios

All run on the synthetic bench home with the window pinned to 1000x733 pt at (0, 29) and the pointer parked at (1100, 500).

| id | what | instrument | numbers |
|---|---|---|---|
| G1 | Home idle: 22 s, then `top -l 41` | none | app %, WindowServer % |
| G2 | Home idle, 30 s, record 20 s | CA Commits, CA Server, Time Profiler | commits, server intervals, server ms, render passes per 20 s |
| G3 | scroll to the bottom of Home, `t0` 2 s after the scroll, 9 s quiet | Time Profiler, Hitches | main busy ms/s over [t0, t0+7), app % there, `scrollable` |
| G4 | History page (Home → History tile), range All (365+ points), pointer sweep 5 s over the centre of the chart's AX frame (`history-chart`) | Time Profiler, Hitches | hitches/s, main busy ms/s |
| G5 | Report sheet (`report-sheet`, opened with `main-report` after the launch report pass has finished), pointer held 4 s on its header row (`ctrl`, 300 pt left of the button) and on its «Show in Finder» button (`capsule`, `report-show-in-finder`; the label dates from the rainbow capsule before REDESIGN-REPORT); traced (G5) and untraced (G5-top) runs | CA Commits, CA Server (+TP, Hitches) | commits/s median, server passes/s; untraced app %, WS % per window |
| G6 | iPhone page, Table and hover scenarios (3 runs) | Time Profiler, Hitches | hitches, ms, main busy total, `rgba64_shade_conic` samples |
| G7 | This Mac scroll | Time Profiler, Hitches | hitches, ms, main busy total, `scrollable` |
| GP:<page> | G7's scroll scenario on the page opened from `home-tile-<page>`; a page whose content fits the window is recorded as an idle page (`scrollable 0`, report heading "IDLE PAGE") | Time Profiler, Hitches | hitches, ms, main busy total, `scrollable` |
| G9 | CPU page idle (Home → CPU tile), 22 s, then `top -l 41` | none | app %, WindowServer % |
| G10 | Home, window width 1060 ↔ 940 twice at 60 Hz via AX (`drv resize`), four crossings of the 1000 pt tier | Time Profiler, Hitches | hitches, ms, main busy total; report-only `sweep_wall_s`, `app_cpu_s`, `ws_cpu_s` (the sweep call only, CPU-s = `top` mean % × wall) |

Limits: G1 and G9 app % <= `--g1-max`; G3 median <= 25 ms/s; G4 hitches/s <= 3, median <= 400 ms/s; G5 `capsule` commits/s median <= 60 and
`capsule` app % <= control + 3; G6 `shade_conic` = 0. Every metric is the median over the runs of an arm. Regression rule against `--baseline`:
the candidate median must not exceed the baseline median by more than the margin (hitches + 3 for G3 G4 G6 G7 GP; main busy total x 1.15 for
G4 G6 G7 GP; app % + 0.5 for G1 G3 G9). A row over its margin is FAIL only when the exact one-sided Mann-Whitney test gives p <= 0.05
(with 3 v 3 runs: every candidate run above every baseline run); otherwise it is NOISY and does not block. A NOISY row is re-run with `--runs 5`.
G10 has no absolute limit; regression rule only, on main busy total x 1.15 (hitches are reported, not gated: a build that is already saturated during a live resize hides the animation cost in them). With `--runs` 1 or 2 a regression is always NOISY; absolute limits still apply. WindowServer numbers are reported, never gated (+-2 pt noise). Scroll scenarios (G3, G7, GP) record `scrollable` per run (1 = the scroll area under the pointer has a vertical scroll bar, 0 = nothing to scroll); when the two arms differ in it, or an arm is mixed, the regression rule is skipped for that scenario ("no regression check") and only absolute limits apply.

## 5. Permissions (as `tools/visual/README.md` §3)

The terminal app that runs the gate needs Screen Recording, Accessibility and Automation → System Events.

## 6. Data safety

- Synthetic data only: `mkfixture.py` builds `$OUT/home` from scratch for every run (500 state rows, 3 iPhones, device 0 with 1026 rows). It refuses a target inside `~/Library`, one that contains the real home, and a non-empty directory it did not create.
- The app is a bench copy (bundle id `com.rdskcm.mac-dashboard.bench`, own defaults domain, saved state deleted at launch) and runs with `CFFIXED_USER_HOME=$OUT/home`. The gate never reads, writes, copies or lists `~/Library/Application Support/MacDashboard`.
- It kills only PIDs it started and recorded in `$OUT/pids`, only while they are still its own children. No `pkill`/`killall`, no kill by name.
- It never installs and never touches `~/Applications/MacDashboard.app`. At exit it calls `tools/ls-prune.sh`.
- The defaults domain is exported before and after and compared; a change is exit 4, never restored.
- AX presses happen only before `xctrace` attaches. Helpers `drv`/`hold` are compiled fresh into `$OUT/.bin/`.

## 7. Known limits

- Time Profiler symbol names (`rgba64_shade_conic`) change with SDKs; re-check them after a macOS/Xcode update.
- `top` timestamps have 1 s samples, so G5 windows hold 3-4 samples each.
- The G3 window is [t0, t0+7) s, i.e. 2-9 s after the scroll ends (R5). A different reading, [t0+2, t0+9), is 4-11 s after it.
- Hitch numbers include whatever the Mac does in the background; a run with the Mac in use is not comparable.
- `scrollable` relies on macOS listing a vertical scroll bar in the AX tree only when the content overflows (true on all nine pages on 2026-10-23, c557d89).
- Security and Backups content comes from the host Mac's real state (updates, crash reports, Time Machine), so GP-security and GP-backups can switch between idle page and scroll from night to night.

## 8. Night runner

`night.sh` builds `origin/main` while the Mac is idle at night, runs the gate on it against the previous night's build and writes a one-screen report to `tools/perf/out/night.noindex/latest.md` (copies in `reports/<YYYYMMDD>.md`; first line `NIGHT <date>: PASS|FAIL|SKIPPED|INTERRUPTED|ERROR …`).

- Preconditions: AC power and Low Power Mode off, screen unlocked, user idle, Claude Code not working (D28), no other gate or night run. A closed lid means no run (the first check after waking writes a SKIPPED report).
- D22: a LaunchAgent runs `night.sh --check` every 60 s; between 00:00 and 03:00 it starts one run per night by opening `night.command` in Terminal, so the run inherits Terminal's Accessibility, Screen Recording and Automation grants (keep them).
- D23: idle threshold 10 min, or the display-sleep time minus 2 min when that is shorter (minimum 60 s).
- D24: `caffeinate -d -i -s` holds the Mac and display awake for the whole run; the report records the assertion.
- D25: the display is dimmed to 0 for the run (`brightness.swift`, DisplayServices or IOKit) and restored at the end, on Ctrl-C and by the next `--check` after a crash; where it cannot be set the run continues and the report says "not settable".
- D26: the candidate is `origin/main` (fetch with BatchMode; offline uses the local ref); the baseline is the previous night's build; the same SHA as the last full measurement is SKIPPED "main unchanged".
- D27: with no earlier finished build there is no baseline, so only absolute limits apply. `builds/` is pruned to the candidate and the baseline only after a successful full measured run (gate exit 0 or 1); after any other exit (also 5, ERROR) or a partial run nothing is deleted, and exit 5 does not mark the SHA as measured, so the next night measures it again.
- D28: `--check` does not start while any Claude Code transcript (`*.jsonl` at any depth under `~/.claude/projects`, main sessions and subagents) was written in the last 15 min; HID idle alone let a run start while agents worked with the user away (2026-10-26). It is the first start condition checked; the skip reason (count, newest write time, path) goes to `agent.log` and, on a night that never starts, into the SKIPPED report.
- The morning report lists the scenarios that had nothing to scroll (`idle page, nothing to scroll …`).
- Install and remove: `tools/perf/night.sh --install` / `--uninstall`. After a restart or crash, `--restore-brightness` puts back a saved value.
- Hand run: `tools/perf/night.sh --run --now` starts a "Mac idle" run at once (skips window and idle checks; ~2.6 h full). `--scenarios G1 --runs 1` takes ~5 min plus the build and is a check of the runner; a run with other scenarios than `all` is marked "partial". `--keep-dark` leaves the display dimmed after the run (for a run started before sleep; the user restores brightness by hand).
- `--check --dry-run` prints the decision and starts nothing. With `NIGHT_HOUR=<0-23>` it decides as at that hour, with `NIGHT_CLAUDE_PROJECTS=<dir>` it looks for transcripts in that folder; with `NIGHT_DATE=<YYYYMMDD>` it decides as for that night (no started marker, its own skip and report files); all three are ignored without `--dry-run`.
