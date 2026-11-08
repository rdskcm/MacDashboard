#!/usr/bin/env python3
"""tools/perf/budgets.py - page budgets (PAGE-BUDGETS): read tools/perf/budgets.tsv and compare tonight's readings with it.

Usage: python3 -I tools/perf/budgets.py get PAGE METRIC [--budgets FILE]
       python3 -I tools/perf/budgets.py read --sha SHA [--gate-root DIR] [--run DIR]... [--budgets FILE]
       python3 -I tools/perf/budgets.py selftest
get:      prints the budget max of PAGE for METRIC exactly as written in the file (the page's own row, else the "*" row).
read:     prints "BUDGETS <o> over, <w> within, <n> no data", then "- " lines (build and sources, over, within, no data,
          traced minus gate). Readings count only when they are of the build SHA: gate runs night-* under --gate-root
          (idle_app_pct of home = G1 and cpu = G9) and MAIN-THREAD-AUDIT manifests given with --run (Time Profiler rows).
          Never fails: any error prints one line "BUDGETS error: <text>".
selftest: fixtures only; prints "selftest ok" or "selftest FAILED: <case>".
Exit: 0 | 2 (get: no such budget or unreadable file) | 1 (selftest failed) | 64 usage.
"""
import csv
import math
import os
import re
import shutil
import sys
import tempfile

PAGES = ("cpu memory storage battery security backups system history home iphone iphone-device report settings").split()
GATE_IDLE = (("home", "G1"), ("cpu", "G9"))
NO_READER = {"frame_ms": "no night job records frame times with the 144 Hz display as main"}
UNITS = {"idle_app_pct": "% of one core", "frame_ms": "ms"}
WORDS = {"idle_app_pct": "idle", "frame_ms": "frame"}
DEFAULT_BUDGETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "budgets.tsv")
HEADER = ["page", "metric", "max", "basis"]
GATE_DIR_RE = re.compile(r"^night-\d{8}(-\d{6})?$")
HEX_RE = re.compile(r"^[0-9a-f]{7,}$")
MIN_WINDOW_S = 5.0


class Num(float):
    """A budget max: a float that remembers how the file wrote it."""
    raw = ""


def load(path):
    """-> dict (page, metric) -> (max, basis); raises ValueError("<path>:<line>: <what>")."""
    out = {}
    header_seen = False
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            if not line.strip() or line.startswith("#"):
                continue
            where = "%s:%d: " % (path, n)
            if not header_seen:
                if line.split("\t") != HEADER:
                    raise ValueError(where + "the first line must be the header page<TAB>metric<TAB>max<TAB>basis")
                header_seen = True
                continue
            parts = line.split("\t")
            if len(parts) != 4:
                raise ValueError(where + "expected 4 tab-separated fields, got %d" % len(parts))
            page, metric, mx, basis = parts
            if not page or not metric:
                raise ValueError(where + "empty page or metric")
            try:
                v = float(mx)
            except ValueError:
                raise ValueError(where + "max is not a number: " + mx)
            if not math.isfinite(v) or v < 0:
                raise ValueError(where + "max must be a finite number >= 0: " + mx)
            if (page, metric) in out:
                raise ValueError(where + "duplicate row for %s %s" % (page, metric))
            num = Num(v)
            num.raw = mx
            out[(page, metric)] = (num, basis)
    if not header_seen:
        raise ValueError("%s:1: missing header" % path)
    return out


def budget(b, page, metric):
    return b.get((page, metric)) or b.get(("*", metric))


def sha_match(a, b):
    if not (HEX_RE.match(a or "") and HEX_RE.match(b or "")):
        return False
    return a == b or a.startswith(b) or b.startswith(a)


def num(s):
    try:
        v = float(s)
    except (TypeError, ValueError):
        return None
    return v if math.isfinite(v) else None


def read_tsv(path):
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def gate_readings(root, sha):
    """-> ({scenario: (value, dir name)}) from the newest valid night-* gate run of this build, per scenario."""
    found = {}
    try:
        names = sorted((n for n in os.listdir(root) if GATE_DIR_RE.match(n)), reverse=True)
    except OSError:
        return found
    for name in names:
        d = os.path.join(root, name)
        try:
            with open(os.path.join(d, "report.md"), encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        cand = [l for l in lines if l.startswith("- candidate:")]
        if not cand:
            continue
        m = re.search(r"/builds/([^/\s`]+)/", cand[0])
        if not m or not sha_match(m.group(1), sha):
            continue
        if any(l.startswith("GATE:") and "invalid=1" in l for l in lines):
            continue
        try:
            rows = read_tsv(os.path.join(d, "summary.tsv"))
        except OSError:
            continue
        for page, scen in GATE_IDLE:
            if scen in found:
                continue
            for r in rows:
                if (r.get("scenario") == scen and r.get("arm") == "cand" and r.get("run") == "agg"
                        and r.get("metric") == "app_pct" and num(r.get("value")) is not None):
                    found[scen] = (num(r["value"]), name)
                    break
    return found


def traced_readings(runs, sha):
    """-> (run dir name or None, {item: (value, None) | (None, reason)}, default reason for an item without a row)."""
    for d in runs:
        try:
            rows = read_tsv(os.path.join(d, "manifest.tsv"))
        except OSError:
            continue
        if not rows or "cpu_ms" not in rows[0]:
            continue
        name = os.path.basename(os.path.normpath(d))
        msha = rows[0].get("sha") or ""
        if not sha_match(msha, sha):
            return name, {}, "MAIN-THREAD-AUDIT recorded build %s, not this build" % msha
        out = {}
        for r in rows:
            if r.get("template") != "Time Profiler":
                continue
            item = r.get("item") or ""
            if item in out:
                continue
            ms, a, b = num(r.get("cpu_ms")), num(r.get("rec_end_epoch")), num(r.get("idle_start_epoch"))
            win = (a - b) if a is not None and b is not None else None
            if r.get("nav") != "ok":
                why = "nav " + (r.get("nav") or "empty")
            elif r.get("toc_ok") != "1":
                why = "toc_ok " + (r.get("toc_ok") or "empty")
            elif r.get("xctrace_rc") != "0":
                why = "xctrace_rc " + (r.get("xctrace_rc") or "empty")
            elif r.get("note"):
                why = "note " + r.get("note")
            elif ms is None or ms < 0:
                why = "cpu_ms not usable"
            elif win is None or win < MIN_WINDOW_S:
                why = "idle window under %d s" % MIN_WINDOW_S
            else:
                out[item] = (ms / win / 10.0, None)
                continue
            out[item] = (None, "recording not usable (%s)" % why)
        return name, out, "no Time Profiler recording of this build"
    return None, {}, "no Time Profiler recording of this build"


def fmt_val(metric, v):
    return "%.2f" % v if metric == "frame_ms" else "%.1f" % v


def fmt_diff(metric, d):
    s = fmt_val(metric, d)
    if metric != "frame_ms" and s == "0.0":
        s = "%.2f" % d
    return s


def cmd_read(args):
    sha, gate_root, runs, bpath = None, None, [], DEFAULT_BUDGETS
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--sha", "--gate-root", "--run", "--budgets") and i + 1 < len(args):
            v = args[i + 1]
            if a == "--sha":
                sha = v
            elif a == "--gate-root":
                gate_root = v
            elif a == "--run":
                runs.append(v)
            else:
                bpath = v
            i += 2
        else:
            return 64, "usage: budgets.py read --sha SHA [--gate-root DIR] [--run DIR]... [--budgets FILE]\n"
    if not sha:
        return 64, "usage: budgets.py read --sha SHA [--gate-root DIR] [--run DIR]... [--budgets FILE]\n"
    try:
        return 0, _read(sha, gate_root, runs, bpath)
    except ValueError as e:
        return 0, "BUDGETS error: %s\n" % e
    except Exception as e:   # the morning report must never break on this
        return 0, "BUDGETS error: %s: %s\n" % (type(e).__name__, e)


def _read(sha, gate_root, runs, bpath):
    b = load(bpath)
    gate = gate_readings(gate_root, sha) if gate_root else {}
    trun, traced, tdefault = traced_readings(runs, sha)
    pages = list(PAGES) + [p for p in traced if p not in PAGES]
    metrics = []
    for (_, m) in b:
        if m not in metrics:
            metrics.append(m)
    over, within, nodata = [], [], []   # nodata: (metric, page, reason)
    for metric in metrics:
        for page in pages:
            bud = budget(b, page, metric)
            if bud is None:
                continue
            mx = bud[0]
            word = WORDS.get(metric, metric)
            reading, label, reason = None, "", ""
            if metric in NO_READER:
                reason = NO_READER[metric]
            elif metric == "idle_app_pct":
                scen = dict((p, s) for p, s in GATE_IDLE).get(page)
                if scen in gate:
                    reading, label = gate[scen][0], "gate " + scen
                elif page in traced and traced[page][0] is not None:
                    reading, label = traced[page][0], "traced"
                else:
                    reason = traced[page][1] if page in traced else tdefault
            else:
                reason = "no reader for this metric"
            if reading is None:
                nodata.append((metric, page, reason, mx))
                continue
            unit = UNITS.get(metric, "")
            head = "- %s %s: %s %s (%s), budget %s" % (page, word, fmt_val(metric, reading), unit, label, mx.raw)
            if reading > mx:
                over.append("%s: over budget by %s %s" % (head, fmt_diff(metric, reading - mx),
                                                          "ms" if metric == "frame_ms" else "pp"))
            else:
                within.append(head + ": within budget")
    lines = ["BUDGETS %d over, %d within, %d no data" % (len(over), len(within), len(nodata))]
    gnames = sorted(set(g[1] for g in gate.values()))
    gpart = ("gate %s (%s)" % (", ".join(gnames), ", ".join("%s %s" % (s, p) for p, s in GATE_IDLE if s in gate))
             if gate else "gate: none for this build")
    tpart = "traced " + trun if trun else "traced: none"
    lines.append("- build %s; %s; %s" % (sha, gpart, tpart))
    # V3 of the spec prints home before cpu although PAGES lists cpu first: readings from the gate come first
    # (GATE_IDLE order), the others follow in PAGES order. Each list is built in PAGES order, so a stable sort suffices.
    gate_rank = dict((p, n) for n, (p, s) in enumerate(GATE_IDLE) if s in gate)
    def by_gate(line):
        page = line[2:].split(" ", 1)[0]
        return gate_rank.get(page, len(GATE_IDLE)) if "(gate " in line else len(GATE_IDLE)
    over.sort(key=by_gate)
    within.sort(key=by_gate)
    lines += over + within
    groups, order = {}, []
    for metric, page, reason, mx in nodata:
        k = (metric, reason)
        if k not in groups:
            groups[k] = []
            order.append(k)
        groups[k].append((page, mx))
    for (metric, reason) in order:
        members = groups[(metric, reason)]
        allp = [p for p in pages if budget(b, p, metric) is not None]
        names = "all pages" if [p for p, _ in members] == allp else ", ".join(p for p, _ in members)
        line = "- %s %s: no data (%s)" % (names, WORDS.get(metric, metric), reason)
        if metric in NO_READER:
            star = b.get(("*", metric))
            mx = star[0] if star else members[0][1]
            line += ", budget %s %s" % (mx.raw, UNITS.get(metric, "")) if UNITS.get(metric) else ", budget " + mx.raw
        lines.append(line)
    both = []
    for page, scen in GATE_IDLE:
        if scen in gate and page in traced and traced[page][0] is not None:
            both.append((page, traced[page][0] - gate[scen][0]))
    if both:
        parts = []
        for page, d in both:
            s = "%+.1f" % d
            if s in ("+0.0", "-0.0"):
                s = "%+.2f" % d
            parts.append("%s %s" % (page, s))
        lines.append("- traced minus gate: %s pp (Time Profiler overhead in the traced readings)" % ", ".join(parts))
    return "\n".join(lines) + "\n"


def cmd_get(args):
    usage = "usage: budgets.py get PAGE METRIC [--budgets FILE]\n"
    pos, bpath, i = [], DEFAULT_BUDGETS, 0
    while i < len(args):
        if args[i] == "--budgets":
            if i + 1 >= len(args):
                return 64, "", usage
            bpath = args[i + 1]
            i += 2
        else:
            pos.append(args[i])
            i += 1
    if len(pos) != 2:
        return 64, "", usage
    try:
        b = load(bpath)
    except (OSError, ValueError) as e:
        return 2, "", "budgets: %s\n" % e
    hit = budget(b, pos[0], pos[1])
    if hit is None:
        return 2, "", "budgets: no budget for %s %s in %s\n" % (pos[0], pos[1], bpath)
    return 0, hit[0].raw + "\n", ""


def run(argv):
    """-> (exit code, stdout, stderr)."""
    if not argv or argv[0] not in ("get", "read", "selftest"):
        return 64, "", "usage: budgets.py get|read|selftest ...\n"
    if argv[0] == "get":
        return cmd_get(argv[1:])
    if argv[0] == "read":
        code, out = cmd_read(argv[1:])
        return code, (out if code == 0 else ""), ("" if code == 0 else out)
    return cmd_selftest()


# ---------------------------------------------------------------- selftest

FIX_BUDGETS = ("# fixture\npage\tmetric\tmax\tbasis\n*\tidle_app_pct\t2.0\tb\ncpu\tidle_app_pct\t5.0\tb\n"
               "*\tframe_ms\t7.0\tb\n")
MANIFEST_COLS = ["seq", "item", "template", "sha", "nav", "rec_end_epoch", "idle_start_epoch", "xctrace_rc", "toc_ok",
                 "cpu_ms", "note"]


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def _gate(root, name, sha, home, cpu, invalid=0):
    d = os.path.join(root, name)
    _write(os.path.join(d, "report.md"), "x\n- candidate: `/o/builds/%s/App.app`\nGATE: exit=0 pass=1 fail=0 noisy=0 invalid=%d error=0\n"
           % (sha, invalid))
    _write(os.path.join(d, "summary.tsv"), "scenario\tarm\trun\tmetric\tvalue\tthreshold\tverdict\n"
           "G1\tcand\tagg\tapp_pct\t%s\t\tPASS\nG9\tcand\tagg\tapp_pct\t%s\t\tPASS\n" % (home, cpu))


def _manifest(path, sha, rows):
    """rows: (item, nav, cpu_ms, window_s)."""
    text = "\t".join(MANIFEST_COLS) + "\n"
    for n, (item, nav, ms, win) in enumerate(rows, 1):
        text += "\t".join(["%02d" % n, item, "Time Profiler", sha, nav, str(1000 + win), "1000", "0", "1", str(ms), ""]) + "\n"
    _write(os.path.join(path, "manifest.tsv"), text)


def cmd_selftest():
    tmp = tempfile.mkdtemp(prefix="budgets-selftest-")
    cases = []
    try:
        bf = os.path.join(tmp, "b.tsv")
        _write(bf, FIX_BUDGETS)
        S = "aaaaaaaaaa"

        def rd(*a):
            return run(["read", "--budgets", bf] + list(a))

        def get(*a, **kw):
            return run(["get"] + list(a) + ["--budgets", kw.get("f", bf)])

        bad = {}
        for name, text in (("nohead", "*\tidle_app_pct\t2.0\tb\n"),
                           ("nonnum", "page\tmetric\tmax\tbasis\n*\tidle_app_pct\tx\tb\n"),
                           ("dup", "page\tmetric\tmax\tbasis\n*\tidle_app_pct\t1\tb\n*\tidle_app_pct\t2\tb\n")):
            bad[name] = os.path.join(tmp, name + ".tsv")
            _write(bad[name], text)
        cases += [("get page row beats *", get("cpu", "idle_app_pct")[:2] == (0, "5.0\n")),
                  ("get falls back to *", get("memory", "idle_app_pct")[:2] == (0, "2.0\n")),
                  ("get unknown metric exits 2", get("home", "nosuch")[0] == 2)]
        for name in bad:
            cases.append(("bad file %s: get exits 2" % name, get("home", "idle_app_pct", f=bad[name])[0] == 2))
            code, out, _ = run(["read", "--sha", S, "--budgets", bad[name]])
            cases.append(("bad file %s: read prints BUDGETS error" % name, code == 0 and out.startswith("BUDGETS error:")))
        # 5 within / over / equal
        g = os.path.join(tmp, "g5")
        _gate(g, "night-20260101", S, "1.5", "5.5")
        out = rd("--sha", S, "--gate-root", g)[1]
        cases.append(("over budget text", "- cpu idle: 5.5 % of one core (gate G9), budget 5.0: over budget by 0.5 pp" in out))
        cases.append(("within", "- home idle: 1.5 % of one core (gate G1), budget 2.0: within budget" in out))
        g = os.path.join(tmp, "g5b")
        _gate(g, "night-20260101", S, "2.0", "5.0")
        out = rd("--sha", S, "--gate-root", g)[1]
        cases.append(("equal to max is within", out.startswith("BUDGETS 0 over, 2 within, 24 no data")))
        # 6 gate beats traced
        r = os.path.join(tmp, "r6")
        _manifest(r, S, [("cpu", "ok", 2600, 20), ("home", "ok", 500, 20), ("memory", "ok", 100, 20)])
        out = rd("--sha", S, "--gate-root", g, "--run", r)[1]
        cases.append(("gate beats traced, minus line", "(gate G9)" in out and "- memory idle: 0.5 % of one core (traced)" in out
                      and "- traced minus gate: home +0.5, cpu +8.0 pp" in out))
        # 7 other sha
        out = rd("--sha", "bbbbbbbbbb", "--gate-root", g, "--run", r)[1]
        cases.append(("other sha: gate ignored, manifest reason", "gate: none for this build" in out
                      and "recorded build %s, not this build" % S in out))
        # 8 invalid
        g8 = os.path.join(tmp, "g8")
        _gate(g8, "night-20260101", S, "1.0", "1.0", invalid=1)
        out = rd("--sha", S, "--gate-root", g8)[1]
        cases.append(("invalid gate ignored", "gate: none for this build" in out))
        # 9 nav MISS
        r9 = os.path.join(tmp, "r9")
        _manifest(r9, S, [("memory", "MISS", 100, 20)])
        out = rd("--sha", S, "--run", r9)[1]
        cases.append(("nav MISS not usable", "memory idle: no data (recording not usable (nav MISS))" in out))
        # 10-12
        code, out, _ = rd("--sha", S, "--gate-root", os.path.join(tmp, "empty"))
        cases.append(("frame line", "- all pages frame: no data (" in out and ", budget 7.0 ms" in out))
        cases.append(("empty: 26 no data", out.startswith("BUDGETS 0 over, 0 within, 26 no data")))
        out = rd("--sha", S, "--gate-root", g, "--run", r)[1]
        head, body = out.splitlines()[0], out.splitlines()[2:]
        o = len([l for l in body if "over budget by" in l])
        w = len([l for l in body if l.endswith("within budget")])
        cases.append(("count matches lines", head.startswith("BUDGETS %d over, %d within, 24 no data" % (o, w))
                      or head.startswith("BUDGETS %d over, %d within," % (o, w))))
        cases.append(("usage exit 64", run(["read"])[0] == 64 and run(["get", "x"])[0] == 64))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for name, ok in cases:
        if not ok:
            return 1, "", "selftest FAILED: " + name + "\n"
    return 0, "selftest ok\n", ""


def main():
    try:
        code, out, err = run(sys.argv[1:])
    except Exception as e:
        if sys.argv[1:2] == ["read"]:
            print("BUDGETS error: %s: %s" % (type(e).__name__, e))
            sys.exit(0)
        raise
    sys.stdout.write(out)
    sys.stderr.write(err)
    sys.exit(code)


if __name__ == "__main__":
    main()
