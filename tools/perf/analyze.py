#!/usr/bin/env python3
"""analyze.py — numbers for the perf gate (from the hunt's sum2.py + ca.py). Run with `python3 -I`.

  analyze.py tp  <prefix> [--win LO HI] [substr ...]
      Time Profiler + Hitches. Reads <prefix>-toc.xml, <prefix>-time-profile.xml, <prefix>-hitches.xml
      and the marks in <prefix>-drv.txt. Window = [first t0 + LO, first t0 + HI) (default: first t0 to
      last t1; no marks: the whole trace). Prints a per-second table and `METRIC <name> <value>` lines.
  analyze.py ca  <prefix> [t0 t1]
      Core Animation commit / server intervals (<prefix>-coreanimation-*.xml): whole-trace totals scaled to
      20 s, plus per-window numbers for every labelled mark pair in <prefix>-drv.txt or for the given
      absolute epochs t0 t1.
  analyze.py top <top-file> <pid> [t0 t1]
      Mean app % and WindowServer % from the sampler output of gate.sh (first sample dropped), optionally
      restricted to the samples whose interval centre lies in [t0, t1).
  analyze.py verdict <out-dir> [--g1-max PCT]
      Reads <out-dir>/runs.tsv, writes summary.tsv, appends the per-scenario tables to report.md, prints
      `COUNTS pass=<k> fail=<m> noisy=<j>`.
  analyze.py selftest
      Checks median() and the exact Mann-Whitney p-value; prints `selftest ok`.

Marks in drv.txt: `t0 <epoch>` / `t1 <epoch>`, or `t0 <label> <epoch>` / `t1 <label> <epoch>`.
Exit: 0 ok, 2 bad input / missing file.
"""
import collections
import itertools
import os
import re
import statistics
import sys
import xml.etree.ElementTree as ET
from datetime import datetime


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
        is_main = "Main Thread" in (th or "")
        if is_main:
            main_t.append(t)
        if subs:
            b = bt.find("backtrace")
            names = [get(f).attrib.get("name", "") for f in (b if b is not None else bt).iter("frame")]
            for s in subs:
                if any(s in n for n in names):
                    sub_all[s] += 1
                    if is_main:
                        sub_main[s] += 1
                        j = int(t - lo)
                        if j < nbins:
                            sub_bin[s][j] += 1

    hit = []
    hpath = prefix + "-hitches.xml"
    if os.path.exists(hpath):
        ht, hget = load(hpath)
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
        window_metrics(label, commits, server, a - epoch0, b - epoch0)


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
    if app:
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


def cmd_selftest(args):
    cases = [
        ("median odd", median([1, 3, 2]) == 2),
        ("median even", median([1, 2, 3, 4]) == 2.5),
        ("mw 3v3 separated", abs(mw_p_greater([3, 4, 5], [0, 1, 2]) - 0.05) < 1e-9),
        ("mw identical", mw_p_greater([1, 2, 3], [1, 2, 3]) > 0.05),
        ("mw 5v5 separated", abs(mw_p_greater([5, 6, 7, 8, 9], [0, 1, 2, 3, 4]) - 1 / 252) < 1e-9),
    ]
    for name, ok in cases:
        if not ok:
            print("selftest FAILED: " + name, file=sys.stderr)
            sys.exit(1)
    print("selftest ok")

# (scenario, metric) -> (op, limit). Candidate arm only. `G1_MAX` is filled from --g1-max.
ABS = {
    ("G3", "main_busy_median_ms_s"): ("<=", 25.0),
    ("G4", "hitches_per_s"): ("<=", 3.0),
    ("G4", "main_busy_median_ms_s"): ("<=", 400.0),
    ("G5", "details.commits_per_s_median"): ("<=", 60.0),
    ("G5-top", "details.app_pct_minus_ctrl"): ("<=", 3.0),
    ("G6-page", "sub.rgba64_shade_conic.all"): ("<=", 0.0),
    ("G6-table", "sub.rgba64_shade_conic.all"): ("<=", 0.0),
    ("G6-hover", "sub.rgba64_shade_conic.all"): ("<=", 0.0),
}
# (scenario, metric) -> (kind, k): candidate must be <= base + k  or  <= base * k  (D15)
REG = {}
for _s in ("G3", "G4", "G6-page", "G6-table", "G6-hover", "G7", "G8"):
    REG[(_s, "hitches_total")] = ("add", 3.0)
for _s in ("G4", "G6-page", "G6-table", "G6-hover", "G7"):
    REG[(_s, "main_busy_total")] = ("mul", 1.15)
REG[("GP", "hitches_total")] = ("add", 3.0)
REG[("GP", "main_busy_total")] = ("mul", 1.15)
REG[("G1", "app_pct")] = ("add", 0.5)
REG[("G3", "app_pct")] = ("add", 0.5)
REG[("G8", "app_pct")] = ("add", 0.5)
REG[("G9", "app_pct")] = ("add", 0.5)

ORDER = ["G1", "G2", "G3", "G4", "G5", "G5-top", "G6-page", "G6-table", "G6-hover", "G7", "G8", "G9"]
TITLES = {
    "G1": "G1 idle-home", "G2": "G2 ca-idle", "G3": "G3 post-scroll-bottom", "G4": "G4 hist-all",
    "G5": "G5 rainbow (traced)", "G5-top": "G5 rainbow (untraced, top)", "G6-page": "G6 iphone page",
    "G6-table": "G6 iphone table", "G6-hover": "G6 iphone hover", "G7": "G7 mac-scroll", "G8": "G8 orphan-bottom",
    "G9": "G9 idle-cpu-page",
}


def fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def check(op, value, limit):
    return value <= limit if op == "<=" else value >= limit


def cmd_verdict(argv):
    if not argv:
        die("usage: analyze.py verdict <out-dir> [--g1-max PCT]")
    out = argv[0]
    g1max = 5.6
    if "--g1-max" in argv:
        g1max = float(argv[argv.index("--g1-max") + 1])
    rules = dict(ABS)
    rules[("G1", "app_pct")] = ("<=", g1max)
    rules[("G9", "app_pct")] = ("<=", g1max)

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
        for label in ("details",):
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

    tsv = ["scenario\tarm\trun\tmetric\tvalue\tthreshold\tverdict"]
    rep = []
    npass = nfail = nnoisy = 0
    for scen in [s for s in ORDER if s in metric_order] + [s for s in metric_order if s not in ORDER]:
        rep.append("### %s" % TITLES.get(scen, scen + " page scroll" if scen.startswith("GP-") else scen))
        rep.append("")
        if have_base:
            rep.append("| metric | candidate | baseline | threshold | verdict |")
            rep.append("|---|---|---|---|---|")
        else:
            rep.append("| metric | candidate | threshold | verdict |")
            rep.append("|---|---|---|---|")
        for name in metric_order[scen]:
            for arm in sorted(arms):
                for run, v in data.get((scen, arm, name), []):
                    tsv.append("%s\t%s\t%s\t%s\t%s\t\trun" % (scen, arm, run, name, fmt(v)))
            cand = agg(scen, "cand", name)
            base = agg(scen, "base", name)
            verdicts = []
            thr_txt = []
            rule = rules.get((scen, name))
            if cand is not None and rule:
                ok = check(rule[0], cand, rule[1])
                verdicts.append("PASS" if ok else "FAIL")
                thr_txt.append("%s %s" % (rule[0], fmt(rule[1])))
            reg = REG.get((scen, name)) or (REG.get(("GP", name)) if scen.startswith("GP-") else None)
            if cand is not None and base is not None and reg:
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
    if len(sys.argv) < 2 or sys.argv[1] not in ("tp", "ca", "top", "verdict", "selftest"):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    {"tp": cmd_tp, "ca": cmd_ca, "top": cmd_top, "verdict": cmd_verdict, "selftest": cmd_selftest}[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
