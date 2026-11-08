#!/usr/bin/env python3
"""tools/perf/standing-diff.py - morning diff of one standing night job against its previous DONE run (NIGHT-STANDING-JOBS).

Usage: python3 -I tools/perf/standing-diff.py NAME PREV_DIR|- CUR_DIR
Output: one status line "<STATUS> <NAME>: <text>", then at most 15 detail lines starting with "- ".
STATUS: SAME | CHANGED | FIRST (nothing earlier to compare) | NORULE (no rule for this output).
The rule is chosen by the files in CUR_DIR: manifest.tsv with a cpu_ms column (MAIN-THREAD-AUDIT rig), summary.md with
a "LEAKCHECK " line (MEMORY-LEAK-CHECK rig). A new standing job adds its rule here.
Exit: 0 | 64 usage.
"""
import csv
import math
import os
import re
import sys

RATIO = 1.25        # a value counts as changed only when it moved by at least x1.25 either way ...
CPU_MS_PER_S = 10   # ... and cpu_ms by at least 1 % of one core over the recording (10 ms per recorded second)
ROWS_MIN = 1000     # ... and SwiftUI rows_total by at least 1000 rows
MAX_LINES = 15
LEAK_RE = re.compile(r"^LEAKCHECK (\S+): leaked bytes (\w+) .*?, leaks (\w+) .*?, footprint (\w+) .*?, "
                     r"(\d+) distinct leak stacks \((\d+) growing\)")


def done(status, name, text, details=()):
    print("%s %s: %s" % (status, name, text))
    details = list(details)
    for d in details[:MAX_LINES]:
        print("- " + d)
    if len(details) > MAX_LINES:
        print("- ... %d more" % (len(details) - MAX_LINES))
    sys.exit(0)


def num(s):
    try:
        v = float(s)
    except (TypeError, ValueError):
        return None
    return v if math.isfinite(v) else None


def moved(a, b, floor):
    if a is None or b is None or abs(b - a) < floor:
        return False
    lo, hi = min(a, b), max(a, b)
    return lo <= 0 or hi / lo >= RATIO


def manifest(d):
    try:
        with open(os.path.join(d, "manifest.tsv"), newline="", encoding="utf-8", errors="replace") as f:
            rows = list(csv.DictReader(f, delimiter="\t"))
    except OSError:
        return None
    if not rows or "cpu_ms" not in rows[0]:
        return None
    return {(r.get("item") or "", r.get("template") or ""): r for r in rows}


def leakline(d):
    try:
        with open(os.path.join(d, "summary.md"), encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("LEAKCHECK "):
                    return line.strip()
    except OSError:
        pass
    return None


def sha(rows):
    return next((r.get("sha") for r in rows.values() if r.get("sha")), "?")


def diff_manifest(name, prev, cur):
    if prev is None:
        done("FIRST", name, "no earlier run with a manifest to compare (sha %s, %d recordings)" % (sha(cur), len(cur)))
    keys = set(prev) | set(cur)
    order = sorted(keys, key=lambda k: ((cur.get(k) or prev.get(k)).get("seq") or "", k[0], k[1]))
    det = []
    for k in order:
        a, b = prev.get(k), cur.get(k)
        label = "%s %s %s" % ((b or a).get("seq") or "", k[0], k[1])
        if a is None:
            det.append(label + ": new recording")
            continue
        if b is None:
            det.append(label + ": missing tonight")
            continue
        parts = []
        for col in ("nav", "toc_ok"):
            if (a.get(col) or "") != (b.get(col) or ""):
                parts.append("%s %s -> %s" % (col, a.get(col) or "?", b.get(col) or "?"))
        secs = num(b.get("record_secs")) or num(a.get("record_secs")) or 60.0
        ca, cb = num(a.get("cpu_ms")), num(b.get("cpu_ms"))
        if moved(ca, cb, secs * CPU_MS_PER_S):
            parts.append("cpu_ms %d -> %d" % (ca, cb))
        if k[1] == "SwiftUI":
            ra, rb = num(a.get("rows_total")), num(b.get("rows_total"))
            if moved(ra, rb, ROWS_MIN):
                parts.append("rows_total %d -> %d" % (ra, rb))
        if parts:
            det.append(label + ": " + ", ".join(parts))
    head = "sha %s -> %s, %d of %d recordings changed" % (sha(prev), sha(cur), len(det), len(keys))
    if det:
        done("CHANGED", name, head, det)
    done("SAME", name, head + " (limits x%.2f, 1 %% of one core, %d SwiftUI rows)" % (RATIO, ROWS_MIN))


def diff_leak(name, pline, cline):
    if pline is None:
        done("FIRST", name, "no earlier run with a LEAKCHECK line to compare", [cline])
    pm, cm = LEAK_RE.match(pline), LEAK_RE.match(cline)
    if not pm or not cm:
        done("NORULE", name, "LEAKCHECK line not in the expected form", [pline, cline])
    fields = ("leaked bytes", "leaks", "footprint", "distinct leak stacks", "growing leak stacks")
    det = ["%s %s -> %s" % (f, pm.group(i + 2), cm.group(i + 2))
           for i, f in enumerate(fields) if pm.group(i + 2) != cm.group(i + 2)]
    head = "sha %s -> %s" % (pm.group(1), cm.group(1))
    if det:
        done("CHANGED", name, head + ", " + "; ".join(det), [pline, cline])
    done("SAME", name, head + ", same trends and leak stack counts")


def main(argv):
    if len(argv) != 4:
        sys.stderr.write(__doc__)
        sys.exit(64)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    name, prev_dir, cur_dir = argv[1], argv[2], argv[3]
    prev_dir = None if prev_dir == "-" else prev_dir
    cur = manifest(cur_dir)
    if cur is not None:
        diff_manifest(name, manifest(prev_dir) if prev_dir else None, cur)
    cline = leakline(cur_dir)
    if cline is not None:
        diff_leak(name, leakline(prev_dir) if prev_dir else None, cline)
    done("NORULE", name, "no diff rule for this output; compare the job lines above by eye")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except SystemExit:
        raise
    except BaseException as e:   # never raise: an unexpected failure is a NORULE line like any other
        name = sys.argv[1] if len(sys.argv) > 1 else "?"
        print("NORULE %s: error in the diff rule (%s); compare the job lines above by eye" % (name, type(e).__name__))
        sys.exit(0)
