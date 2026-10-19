# Perf gate (`tools/perf/`)

## 1. Purpose

`tools/perf/gate.sh` measures the main-thread, Core Animation and WindowServer cost of the real app
(scenarios G1-G9) and compares it with absolute limits and, optionally, with a pre-block build. It
exists because per-frame animation work cannot be seen by the offscreen harness or the visual baseline
(rule `gpu-per-frame`). It runs on every GUI-affecting block, next to `tools/visual/run.sh`.

## 2. Usage

```
tools/perf/gate.sh [--app PATH] [--baseline PATH] [--scenarios G1,G2,...] [--runs N] [--out DIR]
                   [--orphan] [--keep-traces] [--g1-max PCT]
tools/perf/gate.sh -h
```

Typical run, on AC power with Low Power Mode off, about 15 minutes, **do not use the Mac while it runs**
(it moves the real pointer and sends AX actions):

```
cd MacDashboard && ./build_app.sh && tools/perf/gate.sh --baseline tools/perf/out/baseline.noindex/MacDashboard.app
```

- `--app` default `dist.noindex/MacDashboard.app`. `--baseline`: candidate and baseline runs alternate A,B,A,B so drift hits both.
- `--scenarios` default all except G8 (G8 needs `--orphan`). `--runs` default 3 for G1 and G9, 1 for the others.
- `--out` must be inside `tools/perf/out/` (gitignored); default `tools/perf/out/<stamp>`. A reused `--out` keeps the previous `summary`/`report`/`runs` files under a time-stamped name.
- `--keep-traces` keeps the `.trace` bundles and exported XML (10-60 MB each). `*-analysis.txt` is always kept.
- `--g1-max` is the absolute G1 app CPU limit: 5.6 (the level before C7), 2.5 after the process-list fix.

Outputs in the run directory: `summary.tsv` (`scenario arm run metric value threshold verdict`),
`report.md` (one table per scenario, power log, defaults verdict), `power.log`, `*-analysis.txt`, and the
last stdout line `GATE: exit=<n> pass=<k> fail=<m> invalid=<0|1>`.

## 3. Exit codes

`0` pass · `1` any FAIL (absolute or regression rule) · `3` INVALID run: the power check after a run (or a `Using Batt`
entry in `pmset -g log` during it) failed twice; the numbers are discarded, never averaged · `4` the defaults domain
`com.rdskcm.mac-dashboard` differs before/after (the diff is printed; the gate never writes or restores it) · `64` usage ·
`65` precondition refused · `70` runtime error (an AX press missed, the window could not be pinned, xctrace failed).
When several apply: 3 over 4 over 1.

Preconditions (65): AC power and Low Power Mode 0 · screen unlocked · main display at least 1280x800 pt · Accessibility
enabled · `xcrun xctrace version` works · no other `gate.sh` running · bench home not inside `~/Library`.

## 4. Scenarios

All run on the synthetic bench home with the window pinned to 1000x733 pt at (0, 29) and the pointer parked at (1100, 500).

| id | what | instrument | numbers |
|---|---|---|---|
| G1 | This Mac Home idle (baseline build: Overview): 22 s, then `top -l 41` | none | app %, WindowServer % |
| G2 | Home idle, 30 s, record 20 s | CA Commits, CA Server, Time Profiler | commits, server intervals, server ms, render passes per 20 s |
| G3 | scroll to the bottom of Home, `t0` 2 s after the scroll, 9 s quiet | Time Profiler, Hitches | main busy ms/s over [t0, t0+7), app % there |
| G4 | History page (Home → History tile; baseline build: Overview bottom), range «Всё» (365+ points), pointer sweep 5 s | Time Profiler, Hitches | hitches/s, main busy ms/s, `HistoryTrendChart.plot` samples/s |
| G5 | pointer held 4 s on a plain card (ctrl) and on two rainbow-ring buttons; traced and untraced runs | CA Commits, CA Server (+TP, Hitches) | commits/s median, server passes/s; untraced app %, WS % per window |
| G6 | iPhone page, Table and hover scenarios (3 runs) | Time Profiler, Hitches | hitches, ms, main busy total, `rgba64_shade_conic` samples |
| G7 | This Mac scroll | Time Profiler, Hitches | hitches, ms, main busy total |
| G8 | G3 with an orphan launchd plist in the bench home | as G3 | as G3 plus `orphan_visible` |
| G9 | CPU page idle (Home → CPU tile), 22 s, then `top -l 41` | none | app %, WindowServer % |

Limits (this block, GPU-RENDER-AUDIT): G1 and G9 app % ≤ `--g1-max`; G3 median ≤ 25 ms/s; G4 hitches/s ≤ 3, median ≤ 400 ms/s,
plot samples/s ≤ 5; G5 ring commits/s median ≤ 60 and ring app % ≤ control + 3; G6 `shade_conic` = 0. Regression rule
against `--baseline`: hitches ≤ base + 3 (G3 G4 G6 G7 G8), main busy total ≤ base × 1.15 (G4 G6 G7), app % ≤ base + 0.5
(G1 G3 G8 G9). WindowServer numbers are reported, never gated (±2 pt noise). G8 with `orphan_visible=no` gets no verdict.

## 5. Permissions (as `tools/visual/README.md` §3)

The terminal app that runs the gate needs Screen Recording, Accessibility and Automation → System Events.

## 6. Data safety

- Synthetic data only: `mkfixture.py` builds `$OUT/home` from scratch for every run (500 state rows, 3 iPhones, device 0 with 1026 rows). It refuses a target inside `~/Library`, one that contains the real home, and a non-empty directory it did not create.
- The app runs with `CFFIXED_USER_HOME=$OUT/home`. The gate never reads, writes, copies or lists `~/Library/Application Support/MacDashboard`.
- It kills only PIDs it started and recorded in `$OUT/pids`, only while they are still its own children. No `pkill`/`killall`, no kill by name.
- It never installs and never touches `~/Applications/MacDashboard.app`. At exit it calls `tools/ls-prune.sh` like `tools/visual/run.sh` does.
- The defaults domain is exported before and after and compared; a change is exit 4, never restored.
- AX presses happen only before `xctrace` attaches. Helpers `drv`/`hold` are compiled fresh into `$OUT/.bin/`.

## 7. Known limits

- Time Profiler symbol names (`HistoryTrendChart.plot`, `rgba64_shade_conic`) change with SDKs; re-check them after a macOS/Xcode update.
- `top` timestamps have 1 s samples, so G5 windows hold 3-4 samples each.
- The G3 window is [t0, t0+7) s, i.e. 2-9 s after the scroll ends (R5). A different reading, [t0+2, t0+9), is 4-11 s after it.
- Hitch numbers include whatever the Mac does in the background; a run with the Mac in use is not comparable.
