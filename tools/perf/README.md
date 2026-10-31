# Perf gate (`tools/perf/`)

## 1. Purpose

`tools/perf/gate.sh` measures the main-thread, Core Animation and WindowServer cost of the real app
(scenarios G1-G7, G9, G10 and GP:<page>) and compares it with absolute limits and, optionally, with a pre-block build. It
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
- Both bundles are copied with `tools/bench-app.sh` (`MacDashboardBench.app`, bundle id `com.rdskcm.mac-dashboard.bench`) into `$OUT/apps`, removed at exit, and their LaunchServices records dropped by `tools/ls-prune.sh`; the app runs with `-appLanguage en -ApplePersistenceIgnoreState YES`.
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
`65` precondition refused · `70` runtime error before or around a run (cannot create the run directory, bench copy or helper build failed, the fixture could not be built, the app exited at launch, the window could not be pinned, the final verdict step failed), or a shell error: an exit 1 that does not come from the final verdict (bash exits 1 on a set -u abort) is reported as 70, so 1 always means a measured FAIL.
When several apply: 3 over 4 over 5 over 1. An AX miss is retried once after the app is brought to the front (for a
Home tile after a fresh `main-mode-mac` press); this retry is robustness. The 2026-10-20 and 2026-10-30 misses (6 or 7 of 8 Home
tiles, presses with no effect) came from a second MacDashboard process: System Events, asked for the gate's pid, returned the other process's window contents (GATE-AX-MISS). The gate now uses native AX by pid (`ax`) and refuses to start beside another MacDashboard process. After pinning, the AX window frame must equal the pid's on-screen CG window frame, else that run is ERROR (`pin: the AX window of pid … is not its on-screen window`). A second miss writes `<tag>-axdiag/`, stops that app, marks the scenario ERROR
and the gate continues with the next scenario. A trace or analysis failure is not retried: the run is ERROR at once, with the log named in errors.tsv. There is never a coordinate fallback.

Preconditions (65): AC power and Low Power Mode 0 · screen unlocked · main display at least 1280x800 pt · Accessibility
enabled (`ax 0 trusted`) · `xcrun xctrace version` works · no other `gate.sh` running · no MacDashboard process the gate did not start (installed app, dev build, another session's bench copy; listed with pid, parent, start time and command by `tools/perf/foreign-copies.sh list` — quit them first; the gate never closes them, `night.sh` does; `GATE_TEST_ALLOW_FOREIGN=1` runs beside them, for the GATE-AX-MISS verification only) · bench home not inside `~/Library`.

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
| G10 | Home, window width 1060 ↔ 940 pt twice at 60 Hz via AX (`drv resize`), four crossings of the 1000 pt tier | Time Profiler, Hitches | hitches, ms, main busy total; report-only `sweep_wall_s`, `app_cpu_s`, `ws_cpu_s` (the sweep call only; approximate: CPU-s = `top` mean % × wall with `top` at 1 Hz; `n/a` when no sample of that process fell inside the window) |
Retired: G8 (System page breathing Outdated capsule) — PERF-GATE-RETARGET, after REDESIGN-SYSTEM removed the capsule.

Limits: G1 and G9 app % <= `--g1-max`; G3 median <= 25 ms/s; G4 hitches/s <= 3, median <= 400 ms/s; G5 `capsule` commits/s median <= 60 and
`capsule` app % <= control + 3; G6 `shade_conic` = 0. Every metric is the median over the runs of an arm. Regression rule against `--baseline`:
the candidate median must not exceed the baseline median by more than the margin (hitches + 3 for G3 G4 G6 G7 GP; main busy total x 1.15 for
G4 G6 G7 GP; app % + 0.5 for G1 G3 G9). A row over its margin is FAIL only when the exact one-sided Mann-Whitney test gives p <= 0.05
(with 3 v 3 runs: every candidate run above every baseline run); otherwise it is NOISY and does not block. A NOISY row is re-run with `--runs 5`.
G10 has no absolute limit; regression rule only, on main busy total x 1.15 (hitches are reported, not gated: a build that is already saturated during a live resize hides the animation cost in them). With `--runs` 1 or 2 a regression is always NOISY; absolute limits still apply. WindowServer numbers are reported, never gated (+-2 pt noise). Scroll scenarios (G3, G7, GP) record `scrollable` per run (1 = the scroll area under the pointer has a vertical scroll bar, 0 = nothing to scroll); when the two arms differ in it, or an arm is mixed, the regression rule is skipped for that scenario ("no regression check") and only absolute limits apply.

## 5. Permissions (as `tools/visual/README.md` §3)

The terminal app that runs the gate needs Screen Recording and Accessibility (the gate's AX helper `ax` runs as its child). `night.sh` also needs Automation → MacDashboard, for the polite quit of the installed app before the gate and each job.

## 6. Data safety

- Synthetic data only: `mkfixture.py` builds `$OUT/home` from scratch for every run (500 state rows, 3 iPhones, device 0 with 1026 rows). It refuses a target inside `~/Library`, one that contains the real home, and a non-empty directory it did not create.
- The app is a bench copy (bundle id `com.rdskcm.mac-dashboard.bench`, own defaults domain, saved state deleted at launch) and runs with `CFFIXED_USER_HOME=$OUT/home`. The gate never reads, writes, copies or lists `~/Library/Application Support/MacDashboard`.
- It kills only PIDs it started and recorded in `$OUT/pids`, only while they are still its own children. No `pkill`/`killall`, no kill by name.
- It never closes another MacDashboard process; it refuses to start instead (exit 65). `night.sh` closes them (§8).
- It never installs and never touches `~/Applications/MacDashboard.app`. At exit it calls `tools/ls-prune.sh`.
- The defaults domain is exported before and after and compared; a change is exit 4, never restored.
- AX presses happen only before `xctrace` attaches. Helpers `drv`/`hold`/`ax` are compiled fresh into `$OUT/.bin/`; `ax` (`ax.swift`) addresses the app only by pid (`AXUIElementCreateApplication`), never through System Events.

## 7. Known limits

- Time Profiler symbol names (`rgba64_shade_conic`) change with SDKs; re-check them after a macOS/Xcode update.
- `top` timestamps have 1 s samples, so G5 windows hold 3-4 samples each.
- The G3 window is [t0, t0+7) s, i.e. 2-9 s after the scroll ends (R5). A different reading, [t0+2, t0+9), is 4-11 s after it.
- Hitch numbers include whatever the Mac does in the background; a run with the Mac in use is not comparable.
- `scrollable` relies on macOS listing a vertical scroll bar in the AX tree only when the content overflows (true on all nine pages on 2026-10-23, c557d89).
- Security and Backups content comes from the host Mac's real state (updates, crash reports, Time Machine), so GP-security and GP-backups can switch between idle page and scroll from night to night.

## 8. Night runner

`night.sh` is the one launcher for unattended night work: on an idle Mac it runs the gate on `origin/main` when main changed, then the queued night jobs until 09:00, and writes one report for the whole night to `tools/perf/out/night.noindex/latest.md` (copies in `reports/<YYYYMMDD>.md`; a second run on the same date writes `reports/<YYYYMMDD>-2.md`, then `-3` …, never overwriting; `latest.md` is the newest; first line `NIGHT <date>: <gate verdict | SKIPPED | INTERRUPTED | ERROR …>; jobs: …`).

- Preconditions: AC power and Low Power Mode off, screen unlocked, user idle, Claude Code not working (D28), no other gate or night run. A closed lid means no run (the first check after waking writes a SKIPPED report).
- D22: a LaunchAgent runs `night.sh --check` every 60 s; between 00:00 and 03:00 it starts one run per night by opening `night.command` in Terminal, so the run inherits Terminal's Accessibility, Screen Recording and Automation grants (keep them).
- D23: idle threshold 10 min, or the display-sleep time minus 2 min when that is shorter (minimum 60 s).
- D24: `caffeinate -d -i -s` holds the Mac and display awake for the whole run; the report records the assertion.
- D25: the display (DisplayServices or IOKit) and the keyboard backlight (CoreBrightness `KeyboardBrightnessClient`, private framework) are dimmed to 0 for the run (`brightness.swift`) and restored at the end, on Ctrl-C and by the next `--check` after a crash; where one cannot be set the run continues and the report says "not settable". A start value below 0.05 (system idle dim, keyboard auto-off) is not saved and not dimmed, so it is never "restored" as black.
- D26: the candidate is `origin/main` (fetch with BatchMode; offline uses the local ref); the baseline is the previous night's build; the same SHA as the last full measurement is SKIPPED "main unchanged".
- D27: with no earlier finished build there is no baseline, so only absolute limits apply. `builds/` is pruned to the candidate and the baseline only after a successful full measured run (gate exit 0, or 1 with a measured FAIL); after any other exit (also 5, ERROR) or a partial run nothing is deleted, and exit 5 does not mark the SHA as measured, so the next night measures it again.
- D28: `--check` does not start while any Claude Code transcript (`*.jsonl` at any depth under `~/.claude/projects`, main sessions and subagents) was written in the last 15 min; HID idle alone let a run start while agents worked with the user away (2026-10-26). It is the first start condition checked; the skip reason (count, newest write time, path) goes to `agent.log` and, on a night that never starts, into the SKIPPED report.
- D29 (NIGHT-START-LOCK): from 21:00 until the night's run starts, at 03:00 at the latest, `--check` keeps one `caffeinate -d -i -s -t <until 03:00>` alive in its own process group, so the console cannot lock while the run waits for its start conditions (2026-10-31 was skipped: locked at 02:06, Claude Code quiet at 02:07). Not on battery or Low Power Mode, not while the screen is locked; never two. While the user is idle for the idle threshold the display and keyboard are dimmed to 0 through the run's saved-value files (`state/hold-dimmed` marks that the hold owns them); input restores them within one tick. The run ends the hold after its own assertion is verified and keeps the lights dark. Events: `hold: …` in `agent.log`, `evening hold: …` in the report.
- The morning report lists the scenarios that had nothing to scroll (`idle page, nothing to scroll …`).
- Install and remove: `tools/perf/night.sh --install` / `--uninstall`. After a restart or crash, `--restore-brightness` puts back a saved value.
- Hand run: `tools/perf/night.sh --run --now` starts a "Mac idle" run at once (skips window and idle checks) and runs the gate only (~2.6 h full); the queue is untouched. `--now --stop HH:MM` also runs the queued jobs until that time; `--now --stop HH:MM --no-gate` runs jobs only. `--scenarios G1 --runs 1` takes ~5 min plus the build and is a check of the runner; a run with other scenarios than `all` is marked "partial". `--keep-dark` leaves display and keyboard dark after the run (the user restores them by hand).
- `--check --dry-run` prints the decision and starts nothing. With `NIGHT_HOUR=<0-23>` it decides as at that hour, with `NIGHT_CLAUDE_PROJECTS=<dir>` it looks for transcripts in that folder; with `NIGHT_DATE=<YYYYMMDD>` it decides as for that night (no started marker, its own skip and report files); `NIGHT_DATE` is ignored without `--dry-run`, `NIGHT_HOUR` is also honoured with `NIGHT_OUT` (then 3-23 only, so a test tick never opens a real run); `NIGHT_IDLE=<s>` (with `--dry-run` or `NIGHT_OUT`) is the HID idle the evening hold sees, never the start check. `NIGHT_OUT=<absolute dir>` replaces `tools/perf/out/night.noindex` (state, queue, builds, reports) in every mode except `--install`/`--uninstall` and also enables `NIGHT_CLAUDE_PROJECTS`: a day-time test state that never touches the real queue or reports. `--dry-run` creates, writes and logs nothing. `NIGHT_FOREIGN_ONLY` is honoured only with `NIGHT_OUT`.
- **Jobs**: `night.sh --queue-add --name NAME --minutes M --dir DIR --cmd 'COMMAND'` queues a job in `out/night.noindex/queue/` (survives sessions; bad input exits 64); `--queue-list` shows the queue in run order; `--queue-remove ID` removes a waiting job. `minutes` is the time the job needs before the 09:00 stop to be worth starting (the full length of a fixed-length job, the minimum useful time of a job that stops itself at `STOP_AT`). Jobs run in queue order, one at a time, after the gate; a job whose minutes do not fit before the stop is not started, stays queued, and the next one is tried. The job runs in the foreground (`/bin/bash -c`, in DIR, stdin `/dev/null`) in its own process group with `STOP_AT` (stop minus 15 min), `NIGHT_STOP_EPOCH`, `NIGHT_JOB_DATE` and `NIGHT_JOB_ID` in its environment; at 09:00 the group gets SIGTERM and SIGKILL 120 s later. A started job leaves the queue with DONE / FAILED exit N / STOPPED AT 09:00 / INTERRUPTED and the report prints its re-queue command; there is no automatic retry. A job must not detach (`nohup`, `&`): what it leaves behind after its exit is killed.
- **Morning report**: written at the end of the run (gate block, one block per job with its last 3 output lines, the jobs still waiting). For a night without a finished run, the first `--check` after 03:00 writes it (SKIPPED or INTERRUPTED) at any hour, also for yesterday's night; never while a run or gate is alive.
- **Other MacDashboard processes** (GATE-AX-MISS): before the gate and before each job `night.sh` runs `foreign-copies.sh close`. Every copy that is not the installed app (bench copies, `dist.noindex` builds, scratchpad copies) gets SIGTERM, then SIGKILL after 5 s. The installed app (`/Applications` or `~/Applications`, bundle id `com.rdskcm.mac-dashboard`) gets one AppleScript quit with a 15 s limit and is never killed, so an app left open overnight is closed in the morning. The report lists every process found (`pid ppid started command`) and how it was closed. If one is still running, the gate is SKIPPED, or the job is NOT STARTED and stays queued, with the pids in the report. This applies to a hand `--run` too. Test seam: `NIGHT_FOREIGN_ONLY=<pid>` with `NIGHT_OUT` acts on that process only.
- **Rig example**: PERF-EFFECT-BREAKDOWN as a job: `tools/perf/night.sh --queue-add --name perf-effect-night2 --minutes 120 --dir "<project>/inputs/PERF-EFFECT-BREAKDOWN-rig" --cmd "OUT=out/night2 KTRACE_CLEAN=1 REPS=3 MATRIX=<follow-up matrix> ./run.sh"`: `./run.sh` in the foreground, no `nohup`/`&`, no `DIM` (night.sh owns the lights), no `STOP_AT` (night.sh exports it), a fresh `OUT`. night.sh closes MacDashboard processes before the job, so the job needs no quit of its own.
