#!/usr/bin/env python3
"""mkfixture.py — synthetic bench home for the perf gate (R2). No byte of the user's real data is used.

usage: python3 -I mkfixture.py <bench-home-dir> [--orphan]

Builds <home>/Library/Application Support/MacDashboard/ (mode 0700) with
  mac_check_state.json  500 daily rows ending today (port of the hunt's mkstate.sh)
  iphones.json          3 devices; device 0 (newest, so tile 0) has 1026 daily battery rows
With --orphan it also writes <home>/Library/LaunchAgents/com.gate.orphan.plist (a plist whose
program does not exist), never in the real ~/Library/LaunchAgents.

Safety: refuses (exit 2) when the target resolves to, or inside, the real ~/Library or contains the
real home, and when <home> exists, is not empty and lacks the marker file this script writes. An
existing marked <home> is deleted and rebuilt from scratch.
Exit: 0 ok, 2 refused or failed, 64 usage.
"""
import json
import os
import plistlib
import shutil
import sys
from datetime import date, datetime, timedelta, timezone

MARKER = ".gate-fixture-home"


def refuse(msg):
    print("mkfixture: refused: " + msg, file=sys.stderr)
    sys.exit(2)


def inside(path, root):
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    flags = [a for a in argv if a.startswith("--")]
    if len(args) != 1 or any(f != "--orphan" for f in flags):
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    orphan = "--orphan" in flags
    home = os.path.realpath(args[0])

    real_home = os.path.realpath(os.path.expanduser("~"))
    real_lib = os.path.join(real_home, "Library")
    real_data = os.path.join(real_lib, "Application Support", "MacDashboard")
    if inside(home, real_lib):
        refuse("bench home %s is inside %s" % (home, real_lib))
    if inside(real_home, home):
        refuse("bench home %s is the real home or one of its parents" % home)
    target = os.path.realpath(os.path.join(home, "Library", "Application Support", "MacDashboard"))
    if inside(target, real_data) or inside(real_data, target):
        refuse("target %s overlaps the real data folder" % target)

    marker = os.path.join(home, MARKER)
    if os.path.lexists(home):
        if not os.path.isdir(home) or os.path.islink(home):
            refuse("%s is not a plain directory" % home)
        if os.listdir(home) and not os.path.exists(marker):
            refuse("%s is not empty and is not a gate fixture home (no %s)" % (home, MARKER))
        shutil.rmtree(home)
    os.makedirs(home, mode=0o700)
    with open(marker, "w") as f:
        f.write("perf gate synthetic bench home\n")

    data_dir = os.path.join(home, "Library", "Application Support", "MacDashboard")
    os.makedirs(data_dir, mode=0o700)
    os.chmod(data_dir, 0o700)

    today = date.today()

    # mac_check_state.json — same field formulas as mkstate.sh
    rows = []
    for i in range(500):
        rows.append({
            "battery_pct": 80 + i % 15,
            "cycles": 300 + i,
            "date": (today - timedelta(days=499 - i)).strftime("%Y-%m-%d"),
            "disk_free_gb": 120 + (i * 7) % 40,
            "disk_used_gb": 100 + (i * 3) % 30,
            "macos": "26.5.2 (25F84)",
            "swap": "%dMB/2048MB" % (200 + (i * 5) % 900),
        })
    write_json(os.path.join(data_dir, "mac_check_state.json"),
               {"last_run": today.strftime("%Y-%m-%d"), "mac_history": rows})

    # iphones.json — shape of IPhoneStore.Envelope / IPhoneDeviceRecord
    now = datetime.now(timezone.utc).replace(microsecond=0)

    def battery(n):
        pts = []
        for i in range(n):
            health = min(100, 100 - i * 16 // 1025 + (1 if i % 3 == 0 else 0))
            pts.append({
                "day": (today - timedelta(days=n - 1 - i)).strftime("%Y-%m-%d"),
                "cycles": i // 2,
                "healthPercent": health,
                "maxCapacityMAh": 3200 * health // 100,
                "designCapacityMAh": 3200,
                "source": "live" if i >= n - 30 else "import",
            })
        return pts

    devices = []
    for k, (letter, rows_n) in enumerate((("A", 1026), ("B", 40), ("C", 40))):
        devices.append({
            "id": "gate-device-%d" % k,
            "name": "Gate iPhone %s" % letter,
            "marketingName": "iPhone 14 Pro",
            "productType": "iPhone15,2",
            "enclosureColor": None,
            "osVersion": "26.0",
            "lastSeen": (now - timedelta(days=k)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "battery": battery(rows_n),
            "keptArchives": [],
        })
    write_json(os.path.join(data_dir, "iphones.json"), {"devices": devices})

    if orphan:
        agents = os.path.join(home, "Library", "LaunchAgents")
        os.makedirs(agents, mode=0o755)
        with open(os.path.join(agents, "com.gate.orphan.plist"), "wb") as f:
            plistlib.dump({"Label": "com.gate.orphan",
                           "ProgramArguments": ["/nonexistent/gate-orphan-binary"]}, f)

    print("fixture ok: %s (mac rows %d, devices %d, device0 rows %d%s)" %
          (home, len(rows), len(devices), len(devices[0]["battery"]), ", orphan plist" if orphan else ""))


def write_json(path, obj):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")
    os.chmod(path, 0o600)


if __name__ == "__main__":
    main(sys.argv[1:])
