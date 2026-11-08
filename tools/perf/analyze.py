#!/usr/bin/env python3
"""analyze.py — numbers for the perf gate (from the hunt's sum2.py + ca.py). Run with `python3 -I`.

  analyze.py tp  <prefix> [--win LO HI] [substr ...]
      Time Profiler + Hitches. Reads <prefix>-toc.xml, <prefix>-time-profile.xml, <prefix>-hitches.xml
      and the marks in <prefix>-drv.txt. Window = [first t0 + LO, first t0 + HI) (default: first t0 to
      last t1; no marks: the whole trace). Prints a per-second table and `METRIC <name> <value>` lines.
      Exits 2 when the window holds no samples, none on a "Main Thread" thread, or <prefix>-hitches.xml is missing,
      and, with substrings, when no sample in the window has a symbolicated frame.
  analyze.py ca  <prefix> [t0 t1]
      Core Animation commit / server intervals (<prefix>-coreanimation-*.xml): whole-trace totals scaled to
      20 s, plus per-window numbers for every labelled mark pair in <prefix>-drv.txt or for the given
      absolute epochs t0 t1.
      Exits 2 when the commit table has no rows or a window is empty or outside the trace.
  analyze.py top <top-file> <pid> [t0 t1]
      Mean app % and WindowServer % from the sampler output of gate.sh (first sample dropped), optionally
      restricted to the samples whose interval centre lies in [t0, t1).
      Exits 2 when no sample of <pid> falls in the window (ws_pct is printed only when WindowServer was sampled).
  analyze.py verdict <out-dir> --g1-max PCT --g9-max PCT
      Both limits are required; gate.sh reads them from tools/perf/budgets.tsv.
      Reads <out-dir>/runs.tsv, writes summary.tsv, appends the per-scenario tables to report.md, prints
      `COUNTS pass=<k> fail=<m> noisy=<j>`.
      A scenario in runs.tsv whose candidate lacks a metric that has an absolute rule, or a regression rule with a
      baseline value, gets a FAIL row for it.
  analyze.py pos <pos-log>
      Position log of a scroll window (drv wave, SCROLL-BENCH-EDGES): prints `METRIC end_contact_pct`, `METRIC pos_reads`,
      `METRIC motion_s`, and `POS-INVALID <why>` when more than 5 % of the reads are within 3 pt of an end of the range
      or fewer than 50 % of the expected reads were logged. Exit 0 in both cases, 2 on a missing or headerless file.
  analyze.py selftest
      Checks median(), the exact Mann-Whitney p-value, pos_eval(), and that tp, ca, top and verdict refuse missing data and that verdict needs both limits; prints `selftest ok`.

Marks in drv.txt: `t0 <epoch>` / `t1 <epoch>`, or `t0 <label> <epoch>` / `t1 <label> <epoch>`.
Exit: 0 ok, 2 bad input / missing file.
"""
import collections
import contextlib
import io
import itertools
import math
import os
import re
import shutil
import statistics
import sys
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime


POS_CONTACT_PT = 3.0        # a position read within this many points of an end of the range is an end contact
POS_LIMIT_PCT = 5.0         # a window with more than this share of its reads at an end is invalid
POS_MIN_READ_SHARE = 0.5    # a window with fewer than this share of the expected reads is invalid
ADDR_NAME = re.compile(r"^0x[0-9a-fA-F]+$")   # the name xctrace gives a frame it could not symbolicate


def die(msg):
    print("analyze: " + msg, file=sys.stderr)
    sys.exit(2)


def metric(name, value):
    if isinstance(value, float):
        print("METRIC %s %s" % (name, ("%.3f" % value).rstrip("0").rstrip(".")))
    else:
        print("METRIC %s %s" % (name, value))


# ---------------------------------------------------------------- shared helpers

def parse_iso(s):
    """ISO-8601 with 'Z' or '+hh:mm' and any number of fractional digits (Python 3.9 is strict)."""
    s = s.strip().replace("Z", "+00:00")
    m = re.match(r"^(.*?)(\.\d+)?([+-]\d\d:\d\d)$", s)
    if not m:
        return datetime.fromisoformat(s).timestamp()
    base, frac, tz = m.groups()
    frac = (frac or ".0")[:7].ljust(7, "0")
    return datetime.fromisoformat(base + frac + tz).timestamp()


def read_toc(prefix):
    path = prefix + "-toc.xml"
    if not os.path.exists(path):
        die("missing " + path)
    toc = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"<start-date>([^<]+)</start-date>", toc)
    if not m:
        die("no <start-date> in " + path)
    d = re.search(r"<duration>([0-9.]+)</duration>", toc)
    return parse_iso(m.group(1)), (float(d.group(1)) if d else 0.0)


def read_marks(prefix):
    """-> list of (kind, label, epoch); label '' for unlabelled marks."""
    out = []
    path = prefix + "-drv.txt"
    if not os.path.exists(path):
        return out
    for line in open(path, encoding="utf-8", errors="replace"):
        p = line.split()
        if len(p) == 2 and p[0] in ("t0", "t1"):
            try:
                out.append((p[0], "", float(p[1])))
            except ValueError:
                pass
        elif len(p) == 3 and p[0] in ("t0", "t1"):
            try:
                out.append((p[0], p[1], float(p[2])))
            except ValueError:
                pass
    return out


def labelled_windows(marks):
    """-> ordered list of (label, t0, t1) from labelled mark pairs."""
    starts = {}
    out = []
    for kind, label, ep in marks:
        if not label:
            continue
        if kind == "t0":
            starts[label] = ep
        elif label in starts:
            out.append((label, starts.pop(label), ep))
    return out


def load(path):
    """Parse an xctrace export; returns (root, resolve) where resolve follows id/ref pairs."""
    if not os.path.exists(path):
        die("missing " + path)
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        die("cannot parse %s: %s" % (path, e))
    ids = {}
    for e in tree.iter():
        if "id" in e.attrib and "ref" not in e.attrib:
            ids[e.attrib["id"]] = e
    return tree, (lambda e: ids[e.attrib["ref"]] if "ref" in e.attrib else e)


def ns_children(row, get):
    """Row children resolved through refs, grouped by tag."""
    d = collections.defaultdict(list)
    for c in row:
        c = get(c)
        d[c.tag].append(c)
    return d


def interval_rows(path):
    """-> [(start_s, dur_s, [uint32 values])] of a coreanimation-*-interval export."""
    tree, get = load(path)
    out = []
    for row in tree.iter("row"):
        d = ns_children(row, get)
        if not d.get("start-time"):
            continue
        start = int(d["start-time"][0].text) / 1e9
        dur = int(d["duration"][0].text) / 1e9 if d.get("duration") else 0.0
        u32 = [int(x.text) for x in d.get("uint32", []) if x.text and x.text.isdigit()]
        out.append((start, dur, u32))
    return out


def med(values):
    return statistics.median(values) if values else 0


def bins(times, lo, hi):
    """Counts per full 1 s bin starting at lo (at least one bin)."""
    n = max(1, int(hi - lo))
    c = [0] * n
    for t in times:
        if lo <= t < hi:
            j = int(t - lo)
            if j < n:
                c[j] += 1
    return c


# ---------------------------------------------------------------- tp

def cmd_tp(argv):
    if not argv:
        die("usage: analyze.py tp <prefix> [--win LO HI] [substr ...]")
    prefix = argv[0]
    rest = argv[1:]
    win = None
    if rest[:1] == ["--win"]:
        win = (float(rest[1]), float(rest[2]))
        rest = rest[3:]
    subs = rest
    epoch0, dur_s = read_toc(prefix)
    marks = read_marks(prefix)
    plain = [(k, e) for k, lab, e in marks if not lab]
    t0s = [e for k, e in plain if k == "t0"]
    t1s = [e for k, e in plain if k == "t1"]
    if t0s:
        base = t0s[0] - epoch0
        if win:
            lo, hi = base + win[0], base + win[1]
        elif t1s:
            lo, hi = base, t1s[-1] - epoch0
        else:
            lo, hi = base, dur_s
    else:
        lo, hi = (win if win else (0.0, dur_s))
    wlen = hi - lo
    if wlen <= 0:
        die("empty window [%.2f, %.2f) — marks missing or outside the trace" % (lo, hi))

    tree, get = load(prefix + "-time-profile.xml")
    main_t = []
    sub_main = {s: 0 for s in subs}
    sub_all = {s: 0 for s in subs}
    nbins = max(1, int(wlen))
    sub_bin = {s: [0] * nbins for s in subs}
    n_win = 0        # samples inside the window, any thread
    n_symbolic = 0   # of those, samples with at least one symbolicated frame (counted only with substrings)
    for row in tree.iter("row"):
        t = th = bt = None
        for c in row:
            c = get(c)
            if c.tag == "sample-time":
                t = int(c.text) / 1e9
            elif c.tag == "thread":
                th = c.attrib.get("fmt", "")
            elif c.tag == "tagged-backtrace":
                bt = c
        if t is None or bt is None or not (lo <= t < hi):
            continue
        n_win += 1
        is_main = "Main Thread" in (th or "")
        if is_main:
            main_t.append(t)
        if subs:
            b = bt.find("backtrace")
            names = [get(f).attrib.get("name", "") for f in (b if b is not None else bt).iter("frame")]
            if any(n and not ADDR_NAME.match(n) for n in names):
                n_symbolic += 1
            for s in subs:
                if any(s in n for n in names):
                    sub_all[s] += 1
                    if is_main:
                        sub_main[s] += 1
                        j = int(t - lo)
                        if j < nbins:
                            sub_bin[s][j] += 1

    # FIX-LEFTOVERS (GPU-RENDER-AUDIT m3): missing data is bad input, never a row of zeros that passes the gate
    if n_win == 0:
        die("no time-profile samples in the window [%.2f, %.2f) of %s — empty or broken trace"
            % (lo, hi, prefix + "-time-profile.xml"))
    if not main_t:
        die("%d time-profile samples in the window but none on a 'Main Thread' thread — thread label changed?" % n_win)
    if subs and n_symbolic == 0:
        die("none of the %d samples in the window has a symbolicated frame — sub.* counts would be 0 for lack of names"
            % n_win)

    hit = []
    ht, hget = load(prefix + "-hitches.xml")   # a missing export is bad input, not 0 hitches
    for row in ht.iter("row"):
        d = ns_children(row, hget)
        if d.get("start-time") and d.get("duration"):
            hit.append((int(d["start-time"][0].text) / 1e9, int(d["duration"][0].text) / 1e6))
    hit_w = [(s, d) for s, d in hit if lo <= s < hi]

    busy = bins(main_t, lo, hi)
    print("%s: window [%.2f, %.2f) trace-s (%.1f s); marks %s" % (
        os.path.basename(prefix), lo, hi, wlen,
        " ".join("%s%s@%.1f" % (k, ("/" + lab) if lab else "", e - epoch0) for k, lab, e in marks)))
    print("bin(s)  main_busy_ms  hitches  hitch_ms" + "".join("  %s" % s[:24] for s in subs))
    hb = bins([s for s, _ in hit_w], lo, hi)
    hm = [0.0] * len(busy)
    for s, d in hit_w:
        j = int(s - lo)
        if j < len(hm):
            hm[j] += d
    for j, n in enumerate(busy):
        print("%5d  %12d  %7d  %8.0f" % (j, n, hb[j], hm[j]) + "".join("  %24d" % sub_bin[s][j] for s in subs))

    metric("window_s", wlen)
    metric("main_busy_total", len(main_t))
    metric("main_busy_mean_ms_s", len(main_t) / wlen)
    metric("main_busy_median_ms_s", float(med(busy)))
    metric("main_busy_max_ms_s", float(max(busy)))
    metric("hitches_total", len(hit_w))
    metric("hitches_per_s", len(hit_w) / wlen)
    metric("hitch_ms_total", sum(d for _, d in hit_w))
    metric("hitch_ms_max", max([d for _, d in hit_w] + [0.0]))
    for s in subs:
        metric("sub.%s.main" % s, sub_main[s])
        metric("sub.%s.all" % s, sub_all[s])
        metric("sub.%s.main_per_s" % s, sub_main[s] / wlen)


# ---------------------------------------------------------------- ca

def window_metrics(label, commits, server, lo, hi):
    pre = (label + ".") if label else ""
    wlen = hi - lo
    c = [s for s, _, _ in commits if lo <= s < hi]
    sv = [(s, d, u) for s, d, u in server if lo <= s < hi]
    metric(pre + "commits_per_s_median", float(med(bins(c, lo, hi))))
    metric(pre + "commits_per_s_mean", len(c) / wlen)
    metric(pre + "server_intervals_per_s", len(sv) / wlen)
    metric(pre + "server_ms_per_s", 1000.0 * sum(d for _, d, _ in sv) / wlen)
    metric(pre + "render_passes_per_s", sum(u[-1] for _, _, u in sv if u) / wlen)


def cmd_ca(argv):
    if not argv:
        die("usage: analyze.py ca <prefix> [t0 t1]")
    prefix = argv[0]
    epoch0, dur_s = read_toc(prefix)
    commits = interval_rows(prefix + "-coreanimation-commit-interval.xml")
    server = interval_rows(prefix + "-coreanimation-server-interval.xml")
    if not commits:   # FIX-LEFTOVERS (m3): the app commits on every tick; an empty table is a broken export, not 0
        die("no Core Animation commit rows in %s — empty or broken trace" % (prefix + "-coreanimation-commit-interval.xml"))
    span = dur_s if dur_s > 0 else max([s for s, _, _ in commits + server] + [1.0])
    k = 20.0 / span
    print("%s: trace %.1f s; commit rows %d, server rows %d" % (os.path.basename(prefix), span, len(commits), len(server)))
    metric("trace_s", span)
    metric("commits_per_20s", len(commits) * k)
    metric("server_intervals_per_20s", len(server) * k)
    metric("server_ms_per_20s", sum(d for _, d, _ in server) * 1000.0 * k)
    metric("render_passes_per_20s", sum(u[-1] for _, _, u in server if u) * k)
    wins = []
    if len(argv) >= 3:
        wins.append(("w", float(argv[1]), float(argv[2])))
    else:
        wins = labelled_windows(read_marks(prefix))
    for label, a, b in wins:
        lo, hi = a - epoch0, b - epoch0
        if hi <= lo or hi <= 0 or lo >= span:   # FIX-LEFTOVERS (m3): a window off the trace would print zeros
            die("window %s [%.2f, %.2f) is empty or outside the trace (0-%.1f s)" % (label or "-", lo, hi, span))
        window_metrics(label, commits, server, lo, hi)


# ---------------------------------------------------------------- top

def cmd_top(argv):
    if len(argv) < 2:
        die("usage: analyze.py top <top-file> <pid> [t0 t1]")
    path, pid = argv[0], argv[1]
    win = (float(argv[2]), float(argv[3])) if len(argv) >= 4 else None
    if not os.path.exists(path):
        die("missing " + path)
    samples = []   # [(epoch, {app: cpu, ws: cpu})]
    for line in open(path, encoding="utf-8", errors="replace"):
        p = line.split()
        if len(p) >= 2 and p[0] == "S":
            samples.append((float(p[1]), {}))
        elif len(p) >= 5 and p[0] == "P" and samples:
            if p[2] == pid:
                samples[-1][1]["app"] = float(p[4])
            elif p[3] == "WindowServer":
                samples[-1][1]["ws"] = float(p[4])
    samples = samples[1:]   # first sample is cumulative since the process start
    app, ws = [], []
    for ts, d in samples:
        centre = ts - 0.5
        if win and not (win[0] <= centre < win[1]):
            continue
        if "app" in d:
            app.append(d["app"])
        if "ws" in d:
            ws.append(d["ws"])
    print("%s: %d samples after dropping the first%s" % (
        os.path.basename(path), len(samples), (" (window %.1f..%.1f)" % win) if win else ""))
    print("app %%: %s" % " ".join("%.1f" % x for x in app))
    print("ws  %%: %s" % " ".join("%.1f" % x for x in ws))
    print("n: app %d, ws %d" % (len(app), len(ws)))
    if not app:   # FIX-LEFTOVERS (m3): no app sample means the sampler failed, not an idle app
        die("no sample of pid %s%s in %s" % (pid, (" in the window %.1f..%.1f" % win) if win else "", path))
    metric("app_pct", sum(app) / len(app))
    if ws:
        metric("ws_pct", sum(ws) / len(ws))


# ---------------------------------------------------------------- verdict

ALPHA = 0.05


def median(vals):
    s = sorted(vals)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def mw_p_greater(cand, base):
    """Exact one-sided permutation p-value of the Mann-Whitney U statistic; H1: candidate values are larger."""
    def u(xs, ys):
        return sum(1.0 if x > y else 0.5 if x == y else 0.0 for x in xs for y in ys)
    pooled = list(cand) + list(base)
    obs = u(cand, base)
    hits = total = 0
    for comb in itertools.combinations(range(len(pooled)), len(cand)):
        chosen = set(comb)
        xs = [pooled[i] for i in comb]
        ys = [pooled[i] for i in range(len(pooled)) if i not in chosen]
        total += 1
        if u(xs, ys) >= obs - 1e-9:
            hits += 1
    return hits / total


def pos_eval(range_pt, hz, motion_s, values):
    """-> (end_contact_pct, why). values = bar values (0..1) read during the motion; why is "" for a valid window."""
    n = len(values)
    hits = sum(1 for v in values if v * range_pt <= POS_CONTACT_PT or (1 - v) * range_pt <= POS_CONTACT_PT)
    pct = 100.0 * hits / n if n else 0.0
    expected = hz * motion_s
    if n == 0 or motion_s <= 0:
        return pct, "no completed scroll window in the position log (%d reads, %.1f s of motion)" % (n, motion_s)
    if n < POS_MIN_READ_SHARE * expected:
        return pct, "only %d of about %d position reads were logged" % (n, round(expected))
    if pct > POS_LIMIT_PCT:
        return pct, "%.1f %% of %d position reads at an end (limit 5 %%), range %.0f pt" % (pct, n, range_pt)
    return pct, ""


def cmd_pos(argv):
    if len(argv) != 1:
        die("usage: analyze.py pos <pos-log>")
    if not os.path.exists(argv[0]):
        die("missing " + argv[0])
    rng = hz = None
    values, starts, motion = [], [], 0.0
    for line in open(argv[0]):
        p = line.split()
        if not p:
            continue
        if p[0] == "#":
            kv = dict(x.split("=", 1) for x in p[1:] if "=" in x)
            if "range" in kv:
                rng, hz = float(kv["range"]), float(kv.get("hz", 10))
        elif p[0] == "S" and len(p) == 2:
            starts.append(float(p[1]))
        elif p[0] == "E" and len(p) == 2 and starts:
            motion += float(p[1]) - starts.pop()
        elif p[0] == "P" and len(p) == 3:
            values.append(float(p[2]))
    if rng is None:
        die("no '# range=' header in " + argv[0])
    pct, why = pos_eval(rng, hz, motion, values)
    metric("end_contact_pct", pct)
    metric("pos_reads", len(values))
    metric("motion_s", motion)
    if why:
        print("POS-INVALID " + why)


ST_TOC = ('<?xml version="1.0"?><trace-toc><run><info><summary><start-date>2026-11-06T10:00:00.000+00:00'
          '</start-date><duration>30.0</duration></summary></info></run></trace-toc>')
ST_DRV = "t0 1793959205.0\nt1 1793959215.0\n"   # trace seconds 5 and 15 of ST_TOC
ST_EMPTY_TABLE = '<?xml version="1.0"?><trace-query-result><node xpath="x"/></trace-query-result>'


def _run(fn, argv):
    """-> (exit code, stdout) of one analyze.py command run in-process (selftest only)."""
    out = io.StringIO()
    code = 0
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        try:
            fn(argv)
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 1
    return code, out.getvalue()


def _tp_fixture(root, name, thread, rows, hitches, frame="f"):
    """Writes <root>/<name>/t-{toc,drv,time-profile[,hitches]}.xml|txt; `rows` samples at 5.1 s, 5.2 s, ..., each with
    one frame named `frame`; -> prefix."""
    d = os.path.join(root, name)
    os.makedirs(d)
    prefix = os.path.join(d, "t")
    body = "".join(
        '<row><sample-time id="s%d" fmt="x">%d</sample-time><thread fmt="%s"/>'
        '<tagged-backtrace><backtrace><frame name="%s"/></backtrace></tagged-backtrace></row>\n'
        % (i, (5100 + 100 * i) * 1000000, thread, frame) for i in range(rows))
    files = {"-toc.xml": ST_TOC, "-drv.txt": ST_DRV,
             "-time-profile.xml": '<?xml version="1.0"?><trace-query-result><node xpath="x">\n%s</node>'
                                  '</trace-query-result>\n' % body}
    if hitches:
        files["-hitches.xml"] = ST_EMPTY_TABLE
    for suffix, text in files.items():
        with open(prefix + suffix, "w") as f:
            f.write(text)
    return prefix


def _ca_fixture(root, name, commits, marks=""):
    """Writes <root>/<name>/t-toc.xml, both Core Animation interval tables (`commits` rows at 1 s, 2 s, ... in each)
    and t-drv.txt holding `marks`; -> prefix."""
    d = os.path.join(root, name)
    os.makedirs(d)
    prefix = os.path.join(d, "t")
    rows = "".join('<row><start-time>%d</start-time><duration>1000000</duration><uint32>1</uint32></row>\n'
                   % ((i + 1) * 1000000000) for i in range(commits))
    table = '<?xml version="1.0"?><trace-query-result><node xpath="x">\n%s</node></trace-query-result>\n' % rows
    files = {"-toc.xml": ST_TOC, "-drv.txt": marks,
             "-coreanimation-commit-interval.xml": table, "-coreanimation-server-interval.xml": table}
    for suffix, text in files.items():
        with open(prefix + suffix, "w") as f:
            f.write(text)
    return prefix


def _top_fixture(root, name, app_rows):
    """Writes <root>/<name>-top.txt: samples at epochs 1000..1005; pid 42 at 2 % in each when `app_rows`,
    WindowServer at 5 % always; -> the path."""
    path = os.path.join(root, name + "-top.txt")
    with open(path, "w") as f:
        for i in range(6):
            f.write("S %d\n" % (1000 + i))
            if app_rows:
                f.write("P 0 42 MacDashboard 2.0\n")
            f.write("P 0 99 WindowServer 5.0\n")
    return path


def _verdict_fixture(root, name, lines):
    """Writes <root>/<name>/runs.tsv from (scenario, arm, run, metric, value) tuples; -> the directory."""
    d = os.path.join(root, name)
    os.makedirs(d)
    with open(os.path.join(d, "runs.tsv"), "w") as f:
        f.write("".join("\t".join(p) + "\n" for p in lines))
    return d


def cmd_selftest(args):
    cases = [
        ("median odd", median([1, 3, 2]) == 2),
        ("median even", median([1, 2, 3, 4]) == 2.5),
        ("mw 3v3 separated", abs(mw_p_greater([3, 4, 5], [0, 1, 2]) - 0.05) < 1e-9),
        ("mw identical", mw_p_greater([1, 2, 3], [1, 2, 3]) > 0.05),
        ("mw 5v5 separated", abs(mw_p_greater([5, 6, 7, 8, 9], [0, 1, 2, 3, 4]) - 1 / 252) < 1e-9),
        ("pos all mid valid", pos_eval(1000.0, 10, 9.8, [0.5] * 100)[1] == ""),
        ("pos 10 of 100 at end invalid", pos_eval(1000.0, 10, 9.8, [0.5] * 90 + [1.0] * 10)[1] != ""),
        ("pos 10 reads of 98 expected invalid", pos_eval(1000.0, 10, 9.8, [0.5] * 10)[1] != ""),
        ("pos header only invalid", pos_eval(1000.0, 10, 0.0, [])[1] != ""),
        ("pos reads without a completed S/E pair invalid", pos_eval(1000.0, 10, 0.0, [0.5] * 20)[1] != ""),
    ]
    # FIX-LEFTOVERS (GPU-RENDER-AUDIT m3): tp and verdict refuse missing data (inputs as in the hunter's m3/ set)
    tmp = tempfile.mkdtemp(prefix="analyze-selftest-")
    lim = ["--g1-max", "1", "--g9-max", "1"]   # test limits, not budgets: no fixture has a G1 or G9 app_pct value
    try:
        main_label = "Main Thread (0x1) (MacDashboard, pid: 1)"
        ok_code, ok_out = _run(cmd_tp, [_tp_fixture(tmp, "valid", main_label, 10, True)])
        vm_code, vm_out = _run(cmd_verdict, [_verdict_fixture(tmp, "vmissing", [
            ("G3", "cand", "1", "window_s", "10"), ("G4", "cand", "1", "window_s", "10"),
            ("G6-page", "cand", "1", "window_s", "10")])] + lim)
        with open(os.path.join(tmp, "vmissing", "summary.tsv")) as f:
            vm_summary = f.read()
        vz_code, vz_out = _run(cmd_verdict, [_verdict_fixture(tmp, "vzero", [
            ("G3", "cand", "1", "main_busy_median_ms_s", "0"), ("G4", "cand", "1", "main_busy_median_ms_s", "0"),
            ("G4", "cand", "1", "hitches_per_s", "0"), ("G4", "cand", "1", "hitches_total", "0")])] + lim)
        vb_code, vb_out = _run(cmd_verdict, [_verdict_fixture(tmp, "vbase", [
            ("G4", "base", "1", "hitches_per_s", "1"), ("G4", "cand", "1", "main_busy_median_ms_s", "10")])] + lim)
        vi_code, vi_out = _run(cmd_verdict, [_verdict_fixture(tmp, "vinfo", [   # the second hunter's verdict-info set
            ("G4", "cand", "1", "window_s", "20"), ("G4", "cand", "1", "main_busy_total", "0"),
            ("G3", "cand", "1", "app_pct", "1.0"), ("G1", "cand", "1", "ws_pct", "3.0"),
            ("G9", "cand", "1", "ws_pct", "3.0")])] + lim)
        vr_code, vr_out = _run(cmd_verdict, [_verdict_fixture(tmp, "vreg", [
            ("GP-system", "base", "1", "main_busy_total", "900"), ("GP-system", "base", "1", "hitches_total", "2"),
            ("GP-system", "cand", "1", "hitches_total", "2")])] + lim)
        sym_prefix = _tp_fixture(tmp, "named", main_label, 10, True)
        sym_code, sym_out = _run(cmd_tp, [sym_prefix, "rgba64_shade_conic"])
        addr_prefix = _tp_fixture(tmp, "addrs", main_label, 10, True, frame="0x18bbb6d80")
        ca_code, ca_out = _run(cmd_ca, [_ca_fixture(tmp, "ca-ok", 10,
                                                    "t0 capsule 1793959202.0\nt1 capsule 1793959206.0\n")])
        top_ok = _top_fixture(tmp, "top-ok", True)
        top_code, top_out = _run(cmd_top, [top_ok, "42"])
        cases += [
            ("tp substring on a symbolicated trace", sym_code == 0 and "METRIC sub.rgba64_shade_conic.all 0\n" in sym_out),
            ("tp substring on an unsymbolicated trace dies", _run(cmd_tp, [addr_prefix, "rgba64_shade_conic"])[0] == 2),
            ("tp unsymbolicated trace without substrings passes", _run(cmd_tp, [addr_prefix])[0] == 0),
            ("ca valid trace", ca_code == 0 and "METRIC capsule.commits_per_s_mean 1\n" in ca_out),
            ("ca empty commit table dies", _run(cmd_ca, [_ca_fixture(tmp, "ca-empty", 0)])[0] == 2),
            ("ca window outside the trace dies", _run(cmd_ca, [_ca_fixture(
                tmp, "ca-outside", 10, "t0 capsule 1793959300.0\nt1 capsule 1793959304.0\n")])[0] == 2),
            ("top valid samples", top_code == 0 and "METRIC app_pct 2\n" in top_out),
            ("top no app samples dies", _run(cmd_top, [_top_fixture(tmp, "top-noapp", False), "42"])[0] == 2),
            ("top window without samples dies", _run(cmd_top, [top_ok, "42", "2000", "2010"])[0] == 2),
            ("verdict missing ABS metrics of G1 G3 G4 G9 fail", vi_code == 0 and "COUNTS pass=0 fail=5 noisy=0" in vi_out),
            ("verdict REG metric with a baseline but no candidate fails",
             vr_code == 0 and "COUNTS pass=1 fail=1 noisy=0" in vr_out),
        ]
        cases += [
            ("tp valid trace", ok_code == 0 and "METRIC main_busy_total 10\n" in ok_out),
            ("tp no samples in the window dies",
             _run(cmd_tp, [_tp_fixture(tmp, "empty", main_label, 0, True)])[0] == 2),
            ("tp samples but no Main Thread label dies",
             _run(cmd_tp, [_tp_fixture(tmp, "renamed", "Main Thr3ad 0x1 (MacDashboard)", 10, True)])[0] == 2),
            ("tp missing hitches export dies",
             _run(cmd_tp, [_tp_fixture(tmp, "nohitches", main_label, 10, False)])[0] == 2),
            ("verdict missing ABS metrics fail", vm_code == 0 and "COUNTS pass=0 fail=4 noisy=0" in vm_out
             and "G3\tcand\tagg\tmain_busy_median_ms_s\t-\t<= 25; missing for the candidate\tFAIL\n" in vm_summary),
            ("verdict without the limit flags dies", _run(cmd_verdict, [os.path.join(tmp, "vzero")])[0] == 2),
            ("verdict present zeros pass", vz_code == 0 and "COUNTS pass=3 fail=0 noisy=0" in vz_out),
            ("verdict metric only in the baseline fails", vb_code == 0 and "COUNTS pass=1 fail=1 noisy=0" in vb_out),
        ]
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for name, ok in cases:
        if not ok:
            print("selftest FAILED: " + name, file=sys.stderr)
            sys.exit(1)
    print("selftest ok")

# (scenario, metric) -> (op, limit). Candidate arm only. `G1_MAX` is filled from --g1-max,
# `G9_MAX` (G9 app_pct) from --g9-max.
ABS = {
    ("G3", "main_busy_median_ms_s"): ("<=", 25.0),
    ("G4", "hitches_per_s"): ("<=", 3.0),
    ("G4", "main_busy_median_ms_s"): ("<=", 400.0),
    ("G5", "capsule.commits_per_s_median"): ("<=", 60.0),
    ("G5-top", "capsule.app_pct_minus_ctrl"): ("<=", 3.0),
    ("G6-page", "sub.rgba64_shade_conic.all"): ("<=", 0.0),
    ("G6-table", "sub.rgba64_shade_conic.all"): ("<=", 0.0),
    ("G6-hover", "sub.rgba64_shade_conic.all"): ("<=", 0.0),
}
# (scenario, metric) -> (kind, k): candidate must be <= base + k  or  <= base * k  (D15)
REG = {}
for _s in ("G3", "G4", "G6-page", "G6-table", "G6-hover", "G7"):
    REG[(_s, "hitches_total")] = ("add", 3.0)
# G10 (RESIZE-MOTION): main busy total only; hitches are reported, not gated (the pre-block build is already saturated
# during a live resize, so hitches cannot see the animation cost)
for _s in ("G4", "G6-page", "G6-table", "G6-hover", "G7", "G10"):
    REG[(_s, "main_busy_total")] = ("mul", 1.15)
REG[("GP", "hitches_total")] = ("add", 3.0)
REG[("GP", "main_busy_total")] = ("mul", 1.15)
REG[("G1", "app_pct")] = ("add", 0.5)
REG[("G3", "app_pct")] = ("add", 0.5)
REG[("G9", "app_pct")] = ("add", 0.5)

ORDER = ["G1", "G2", "G3", "G4", "G5", "G5-top", "G6-page", "G6-table", "G6-hover", "G7", "G9", "G10"]
TITLES = {
    "G1": "G1 idle-home", "G2": "G2 ca-idle", "G3": "G3 post-scroll-bottom", "G4": "G4 hist-all",
    "G5": "G5 rainbow (traced)", "G5-top": "G5 rainbow (untraced, top)", "G6-page": "G6 iphone page",
    "G6-table": "G6 iphone table", "G6-hover": "G6 iphone hover", "G7": "G7 mac-scroll",
    "G9": "G9 idle-cpu-page", "G10": "G10 resize-sweep",
}


def fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def check(op, value, limit):
    return value <= limit if op == "<=" else value >= limit


def cmd_verdict(argv):
    usage = ("usage: analyze.py verdict <out-dir> --g1-max PCT --g9-max PCT "
             "(gate.sh passes the page budgets from tools/perf/budgets.tsv)")
    if not argv:
        die(usage)
    out = argv[0]
    lim = {}
    for flag in ("--g1-max", "--g9-max"):   # both limits come from the required flags, no default numbers
        try:
            v = float(argv[argv.index(flag) + 1])
        except (ValueError, IndexError):
            die(usage)
        if not math.isfinite(v):
            die(usage)
        lim[flag] = v
    g1max, g9max = lim["--g1-max"], lim["--g9-max"]
    rules = dict(ABS)
    rules[("G1", "app_pct")] = ("<=", g1max)
    rules[("G9", "app_pct")] = ("<=", g9max)

    runs_path = os.path.join(out, "runs.tsv")
    if not os.path.exists(runs_path):
        die("missing " + runs_path)
    data = collections.defaultdict(list)       # (scen, arm, metric) -> [(run, value)]
    metric_order = collections.OrderedDict()   # scen -> [metric]
    for line in open(runs_path):
        p = line.rstrip("\n").split("\t")
        if len(p) != 5:
            continue
        scen, arm, run, name, val = p
        try:
            v = float(val)
        except ValueError:
            continue
        data[(scen, arm, name)].append((run, v))
        metric_order.setdefault(scen, [])
        if name not in metric_order[scen]:
            metric_order[scen].append(name)
    arms = {a for (_, a, _) in data}
    have_base = "base" in arms

    # derived: <label>.app_pct_minus_ctrl for G5-top, per arm and per run
    for arm in sorted(arms):
        for label in ("capsule",):
            ctrl = dict(data.get(("G5-top", arm, "ctrl.app_pct"), []))
            for run, v in data.get(("G5-top", arm, label + ".app_pct"), []):
                if run in ctrl:
                    data[("G5-top", arm, label + ".app_pct_minus_ctrl")].append((run, v - ctrl[run]))
                    metric_order.setdefault("G5-top", [])
                    if label + ".app_pct_minus_ctrl" not in metric_order["G5-top"]:
                        metric_order["G5-top"].append(label + ".app_pct_minus_ctrl")

    def agg(scen, arm, name):
        vs = vals(scen, arm, name)
        return median(vs) if vs else None

    def vals(scen, arm, name):
        return [v for _, v in data.get((scen, arm, name), [])]

    def cell(scen, arm, name):
        vs = vals(scen, arm, name)
        if not vs:
            return "-"
        return "%s (%s-%s)" % (fmt(median(vs)), fmt(min(vs)), fmt(max(vs)))

    def scroll_runs(scen, arm):
        """-> (runs with scrollable 0, runs with a scrollable value) for one arm (PERF-GATE-RETARGET)."""
        vs = vals(scen, arm, "scrollable")
        return sum(1 for v in vs if v == 0), len(vs)

    tsv = ["scenario\tarm\trun\tmetric\tvalue\tthreshold\tverdict"]
    rep = []
    npass = nfail = nnoisy = 0
    for scen in [s for s in ORDER if s in metric_order] + [s for s in metric_order if s not in ORDER]:
        title = TITLES.get(scen, scen + " page scroll" if scen.startswith("GP-") else scen)
        c0, cn = scroll_runs(scen, "cand")
        b0, bn = scroll_runs(scen, "base")
        if c0 or b0:
            parts = ["candidate %d of %d runs" % (c0, cn)]
            if have_base:
                parts.append("baseline %d of %d runs" % (b0, bn))
            title += " — IDLE PAGE: nothing to scroll (%s); measured as an idle page, not as a scroll" % ", ".join(parts)
        rc, rb = agg(scen, "cand", "range_pt"), agg(scen, "base", "range_pt")
        if rc is not None and rb is not None and abs(rc - rb) > 0.10 * abs(rb):
            title += " — RANGE DIFFERS: candidate %s pt, baseline %s pt (same speed and motion time)" % (fmt(rc), fmt(rb))
        # the regression rule compares like with like: both arms scrolled in every run, or neither arm did in any run
        same_scroll = (cn == 0 and bn == 0) or (cn > 0 and bn > 0 and c0 in (0, cn) and b0 in (0, bn) and (c0 == 0) == (b0 == 0))
        rep.append("### %s" % title)
        rep.append("")
        if have_base:
            rep.append("| metric | candidate | baseline | threshold | verdict |")
            rep.append("|---|---|---|---|---|")
        else:
            rep.append("| metric | candidate | threshold | verdict |")
            rep.append("|---|---|---|---|")
        # FIX-LEFTOVERS (GPU-RENDER-AUDIT m3): a thresholded metric the candidate never emitted is a FAIL, not an INFO row
        names = metric_order[scen] + [n for (s, n) in rules if s == scen and n not in metric_order[scen]]
        for name in names:
            for arm in sorted(arms):
                for run, v in data.get((scen, arm, name), []):
                    tsv.append("%s\t%s\t%s\t%s\t%s\t\trun" % (scen, arm, run, name, fmt(v)))
            cand = agg(scen, "cand", name)
            base = agg(scen, "base", name)
            verdicts = []
            thr_txt = []
            rule = rules.get((scen, name))
            if rule and cand is None:
                verdicts.append("FAIL")
                thr_txt.append("%s %s; missing for the candidate" % (rule[0], fmt(rule[1])))
            elif rule:
                ok = check(rule[0], cand, rule[1])
                verdicts.append("PASS" if ok else "FAIL")
                thr_txt.append("%s %s" % (rule[0], fmt(rule[1])))
            reg = REG.get((scen, name)) or (REG.get(("GP", name)) if scen.startswith("GP-") else None)
            if reg and cand is None and base is not None:
                verdicts.append("FAIL")
                thr_txt.append("regression rule; missing for the candidate")
            elif cand is not None and base is not None and reg and not same_scroll:
                thr_txt.append("no regression check: candidate and baseline differ in scrollable")
            elif cand is not None and base is not None and reg:
                margin = reg[1] if reg[0] == "add" else base * (reg[1] - 1.0)
                if cand - base <= margin:
                    verdicts.append("PASS")
                    thr_txt.append("median delta <= %s" % fmt(margin))
                else:
                    p = mw_p_greater(vals(scen, "cand", name), vals(scen, "base", name))
                    verdicts.append("FAIL" if p <= ALPHA else "NOISY")
                    thr_txt.append("median delta %s > %s, p=%.3f (fail if p <= %.2f)" % (fmt(cand - base), fmt(margin), p, ALPHA))
            verdict = "FAIL" if "FAIL" in verdicts else "NOISY" if "NOISY" in verdicts else "PASS" if verdicts else "INFO"
            npass += verdicts.count("PASS")
            nfail += verdicts.count("FAIL")
            nnoisy += verdicts.count("NOISY")
            thr = "; ".join(thr_txt)
            if cand is not None:
                tsv.append("%s\tcand\tagg\t%s\t%s\t%s\t%s" % (scen, name, fmt(cand), thr, verdict))
            elif verdicts:
                tsv.append("%s\tcand\tagg\t%s\t-\t%s\t%s" % (scen, name, thr, verdict))
            if base is not None:
                tsv.append("%s\tbase\tagg\t%s\t%s\t\tref" % (scen, name, fmt(base)))
            row = [name, cell(scen, "cand", name)]
            if have_base:
                row.append(cell(scen, "base", name))
            row += [thr or "-", verdict]
            rep.append("| " + " | ".join(row) + " |")
        rep.append("")
    with open(os.path.join(out, "summary.tsv"), "w") as f:
        f.write("\n".join(tsv) + "\n")
    with open(os.path.join(out, "report.md"), "a") as f:
        f.write("\n".join(rep) + "\n")
    print("COUNTS pass=%d fail=%d noisy=%d" % (npass, nfail, nnoisy))


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("tp", "ca", "top", "verdict", "selftest", "pos"):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    {"tp": cmd_tp, "ca": cmd_ca, "top": cmd_top, "verdict": cmd_verdict, "selftest": cmd_selftest, "pos": cmd_pos}[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
