[Русская версия](README.ru.md)

# MacDashboard

Native SwiftUI app for diagnosing your Mac: no browser, no local server,
no dependencies — just one window. Bilingual — English and Russian,
switchable anytime in Settings.

## Screenshots

| Overview (light) | Overview (dark) |
| --- | --- |
| ![Overview: CPU, memory, swap, disk and battery tiles, recommendations](docs/screenshots/overview-light.png) | ![Overview in dark appearance: CPU, memory, swap, disk and battery tiles, recommendations](docs/screenshots/overview-dark.png) |

| Settings | Battery popover |
| --- | --- |
| ![Settings: sidebar navigation with General and Monitoring pages](docs/screenshots/settings.png) | ![Battery popover: power, voltage, temperature, capacity and health](docs/screenshots/battery-popover.png) |

## About this project

I'm not a developer — not even a programmer. I got curious what building
software actually feels like now, with AI in the loop, and I picked a topic I
genuinely cared about: the health of my own Mac. This app is the result,
built together with Claude Code. Now I'm sharing it, in case it's useful to
someone else too.

I plan to keep developing it further — I already have a few ideas. I'm
building this on my own Claude subscription, which limits how much I can get
done, but I find all of this genuinely fascinating. I also don't have an
Apple Developer license yet — it isn't cheap — so the ready-to-download `.app`
isn't notarized and needs a one-time Gatekeeper step on first launch (see
**Install** below); you can also just build it yourself from source. I've tried to respect privacy
and openness as much as realistically possible. I'd be glad to hear your
feedback and comments. Hope you like it!

## What it does

- On launch it automatically checks the whole system (disk, memory,
  security, Time Machine, login items/autostart, disk SMART data, battery,
  Homebrew, macOS updates) and saves the report — a short summary on top
  (status and open tasks, CPU, memory, storage, battery, security, backups,
  uptime), the full details below it; the same text the Report sheet shows — to
  `~/Library/Application Support/MacDashboard/mac_report.txt` — always a
  single file, each run overwrites the previous one.
- Live metrics (CPU, memory, swap, disk, battery) refresh every 2 seconds by
  default; the interval is configurable — 1/2/3/5/10 s — in Settings → Monitoring.
  The process lists refresh every 6 seconds. Switching a card between "Chart" and
  "Table" view doesn't stop the updates — both views read from the same live data.
- History (disk usage over time, battery cycles) accumulates in
  `~/Library/Application Support/MacDashboard/mac_check_state.json`
  (compatible with the old file format).
- Detects recent crash logs (7-day window), grouped and collapsed, and flags
  own-app crashes vs. system panics.
- SOC and internal-disk temperatures, read via Apple Silicon's private HID sensor API.
- A handful of one-click maintenance actions, each explicit and confirmed
  (see "What it can change" below): cleaning up orphaned autostart entries,
  installing `smartmontools` for SMART data on external drives, refreshing
  the Time Machine status, running `brew upgrade`, enabling the firewall,
  emptying the Trash, and tweaking a couple of energy-saver settings.

## What it can change

By default MacDashboard only reads: it collects information and writes its
own report/history files under Application Support and, only when you choose to keep an
imported iPhone sysdiagnose, that archive in the folder shown in Settings › iPhone (default
`~/Documents/MacDashboard/iPhone`; if Documents syncs to iCloud Drive, kept archives sync with
it) — nothing else. The only
exceptions are actions you explicitly click, each of which shows a
confirmation dialog (and, where the system requires it, a Touch ID / admin
password prompt) before doing anything:

- `brew upgrade` — upgrading installed Homebrew packages.
- installing `smartmontools` — so SMART attributes can be read on external
  NVMe/SSD drives.
- toggling the firewall on.
- changing an energy-saver (`pmset`) setting.
- emptying the Trash.
- removing an orphaned autostart entry (a login item / launch agent whose
  target executable no longer exists).

Nothing else in the app touches system state. If you never click one of the
buttons above, the app never changes anything.

## Privacy

MacDashboard does not upload your diagnostic data, reports or history. The
few network requests it makes are all listed below, each with exactly what it
sends. There is no telemetry, no analytics, no crash reporting, no
auto-update check, and no account of any kind.

Every report and history file MacDashboard writes stays in
`~/Library/Application Support/MacDashboard/` on this Mac. Nothing is
uploaded.

**Honest network disclosure.** MacDashboard is not silent on the network —
here is everything it does:

- Collecting a report runs `softwareupdate -l`, which contacts Apple's own
  update service exactly as System Settings does. This sends none of your
  diagnostic data — only the same check Apple itself performs.
- If Homebrew is installed, collecting a report runs `brew update`, which
  downloads Homebrew's package list from Homebrew's own servers exactly as
  running it in Terminal does, and then `brew outdated`, which reads that list
  locally. Neither sends your diagnostic data.
- The two actions you have to click yourself — Homebrew upgrade and
  installing `smartmontools` — download through Homebrew as usual.

The app's own code has no telemetry and uses the network only when you
click a control that says what it does. Nothing goes out at launch, on a
timer or when a phone is attached. The iPhone firmware feature (being
built; not visible in the app yet) contacts exactly these hosts:

- `itunes.apple.com`, when you click "Check with Apple": it downloads
  Apple's public device-software catalogue. Nothing about your phone is sent.
- `api.ipsw.me`, a third-party service, only when you click its own
  "Ask ipsw.me" button: the request contains your phone's model identifier
  (for example `iPhone18,2`) and nothing else.
- `updates.cdn-apple.com` or `secure-appldnld.apple.com`, when you click
  "Download": the restore image (`.ipsw`) Apple's catalogue names, over
  https only, saved to `~/Downloads` after its size and checksums are
  verified. The first save may make macOS ask whether MacDashboard may
  access your Downloads folder; if you decline, the app says so and points
  to System Settings › Privacy & Security › Files and Folders.

Every request also shows the server your Mac's IP address and
`MacDashboard/<version>` as its user agent. Your phone's UDID, ECID, serial
number and name are never sent anywhere. Nothing else touches the network.

**There is no AI assistant in the app.** An unfinished one, never part of a
release, was removed from the code; its last state is kept under the git tag
`ai-assistant-archive`.

**What's in the report.** The diagnostic report MacDashboard collects is
machine-identifying: it can include folder names, installed-app hints,
running process names, and your Time Machine destination name. This stays
entirely local — but if you ever choose to share a report (for example,
filing a bug), you're sharing that detail too. See the issue template's
privacy notice before attaching anything.

## Requirements

- macOS 14 (Sonoma) or newer on an Apple Silicon Mac. Intel Macs: use [v2.1](https://github.com/rdskcm/MacDashboard/releases/tag/v2.1), the last release built for them.
- Nothing to install. Optionally: `smartmontools` (`brew install
  smartmontools`) to see SMART attributes for external NVMe drives — the app
  can also install it for you with one click.

## Install

Two ways — pick one.

### Download the ready-made app (easiest)

> **Intel Mac?** Version 2.2 and later run on Apple Silicon only. On an Intel Mac, download `MacDashboard.zip` from the [v2.1 release](https://github.com/rdskcm/MacDashboard/releases/tag/v2.1) instead — it is the last version built for Intel.

1. Open the [Releases](../../releases) page and download `MacDashboard.zip` from the latest release.
2. *Optional — verify the download.* Compare the hash against the **SHA-256** line in the release notes:
   ```bash
   shasum -a 256 MacDashboard.zip
   ```
3. Unzip and move `MacDashboard.app` into `/Applications` (or `~/Applications`).
4. **First launch — a one-time Gatekeeper step.** The app is ad-hoc signed but
   *not notarized* (I don't have an Apple Developer certificate yet), so the first
   time you open a copy downloaded from the internet macOS blocks it. Clear it once,
   either way:

   **Via System Settings (no Terminal):**
   1. Double-click `MacDashboard.app`. macOS shows **"MacDashboard" Not Opened** — click **Done** (this first dialog deliberately offers no "open" button).
   2. Open **System Settings → Privacy & Security** and scroll down to the *Security* section. Next to **"MacDashboard" was blocked to protect your Mac** click **Open Anyway**.
   3. In the **Open "MacDashboard"?** dialog click **Open Anyway** again, then authenticate with Touch ID or your password.

   > On macOS 15 (Sequoia) and later the old "right-click → Open" trick no longer bypasses Gatekeeper — use System Settings or the Terminal command below.

   **Or in Terminal — one command, same effect:**
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacDashboard.app
   ```
   then open the app normally.

   That's it — every later launch opens with no prompt.

### Build from source

Requires **Xcode 26 (Tahoe SDK)** with its command-line tools selected — the app
uses SwiftUI API (`.onGeometryChange`) that only ships in that SDK, so an older
Xcode will fail to compile it. This is a build-time requirement only; the built
app still runs on macOS 14 (Sonoma) and later.

```bash
git clone https://github.com/rdskcm/MacDashboard.git
cd MacDashboard
./build_app.sh            # builds dist.noindex/MacDashboard.app
./build_app.sh --install  # ...and moves it into ~/Applications
```

An app you build yourself carries no download quarantine, so it opens with no Gatekeeper prompt at all.

Optional, once per Mac: `tools/signing/make-identity.sh` creates a local
self-signed signing certificate in your login keychain, and every later
`./build_app.sh` signs with it. macOS then recognises each rebuild as the same
app, so Full Disk Access and the other permissions survive rebuilds. Without it
the build is ad-hoc signed (the build prints a warning), and macOS asks for those
permissions again after a rebuild with changed code. The script may show one
keychain dialog: enter your login password and click **Always Allow**.

## First launch

On first launch macOS will ask for a couple of permissions (you can decline —
the corresponding sections will simply show "unavailable" instead of crashing):

- access to the Downloads/Documents/Desktop folders — for the "what's taking up space" breakdown;
- control over "System Events" — to read the Login Items (autostart) list.

### Full Disk Access

Without **Full Disk Access** macOS hides some folders from the app, and the
"what's taking up space" breakdown silently loses them — the Trash in particular.
The app no longer stays quiet about it: the affected Folders tab shows a calm line
naming what it could not see, with a button that opens the right System Settings
pane, and one matching recommendation appears in the summary.

To grant it: **System Settings → Privacy & Security → Full Disk Access → +**, pick
`MacDashboard.app` (or switch it on if it is already listed). macOS restarts the app
afterwards.

A separate, unrelated grant: the **Empty the Trash** action drives Finder through
Automation, so the first time you use it macOS asks for permission to control
"Finder". Declining leaves the Trash untouched and shows Finder's own message —
nothing else in the app is affected.

Missing hardware (no battery on a desktop Mac, no external disks, Time Machine
not configured) is a normal, expected state: the relevant cards hide themselves
or show a calm "not set up / none" instead of an error.

## Moving to another Mac

Copy `MacDashboard.app` over (AirDrop, USB drive, whatever). If it picked up a
quarantine flag along the way, clear it exactly as in the first-launch step above.

## Structure

- `Sources/MacDashboard/` — the app itself (SwiftUI, no external dependencies).
- `Tests/MacDashboardTests/` — swift-testing suite: parser, assessment and engine tests (`swift test`, needs Xcode).
- `Tests/Fixtures/` — captured command outputs the parser checks run against (see its README).
- `tools/visual/run.sh` — visual baseline: captures the real app windows and compares them with reference screenshots (dev tool).
- `build_app.sh` — Apple Silicon (arm64) build + `.app` packaging + codesign (the local signing identity if present, otherwise ad-hoc).
- `tools/signing/make-identity.sh` — one-time creation of that local signing identity.
- `SPEC.md` — the original build-out brief. Part of it is still binding (data
  contracts, collectors, packaging); the rest records how v1.0 was built. Each section
  is labelled — see the status table at the top of the file.

## Feedback

Found a bug or have a feature idea? Open an
[Issue](https://github.com/rdskcm/MacDashboard/issues) — the bug and feature
templates will guide you (the bug template also explains what's safe to
attach and what isn't; see the Privacy section above before including a
report file or screenshot). Found a security issue? See
[`SECURITY.md`](SECURITY.md) for how to report it privately instead.

## License

MIT — see [`LICENSE`](LICENSE).

## Acknowledgments

Nearly all of the code was written from scratch for this project — nothing
else was copied from elsewhere. One narrow technical technique was adapted
from open-source prior art:

- Reading Apple Silicon temperature sensors via the private
  `IOHIDEventSystemClient` API
  (`Sources/MacDashboard/Engine/ThermalHIDReader.swift`) follows a publicly
  documented technique used by [exelban/stats](https://github.com/exelban/stats)
  (MIT license) and the [smctemp](https://github.com/narugit/smctemp) project.
  The technique itself — the specific private `IOHIDEventSystemClient*`
  symbols that IOKit.framework exports but doesn't declare in its public
  headers — comes from there; the implementation here (runtime `dlopen`/`dlsym`
  symbol resolution, plus a small C spike in `tools/thermal_probe.c`) was
  written independently for this codebase.

---

"HAPPINESS FOR EVERYBODY, FREE, AND NO ONE WILL GO AWAY UNSATISFIED!"

— Arkady and Boris Strugatsky, *Roadside Picnic* (1972), translated by Antonina W. Bouis.
