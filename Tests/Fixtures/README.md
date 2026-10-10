# Tests/Fixtures

Parser fixtures for R3-FIXTURES: one directory per `ParsedCommand` rawValue
(`Sources/MacDashboard/Engine/ParsedCommands.swift`), found by
`Checks/ParserFixtureChecks.swift` via `#filePath`, no Swift edit needed to add one.

## Naming law
- a real capture (scrubbed) is `<command>-macos<major.minor>.txt` or
  `<command>-macos<major.minor>-<variant>.txt` and must parse. `<command>` is the directory name;
  `<major.minor>` is the first two components of `sw_vers -productVersion` on the Mac it was
  captured on (`26.3.1` → `26.3`); `<variant>` is lowercase words joined by `-` describing the
  machine or state (`laptop`, `desktop`, `not-configured`, …).
- a name containing `synthetic` is hand-built, must parse and needs no version. Its provenance
  is listed below.
- `neg-<what>.txt` must be rejected by the command's parser and needs no version.
- every subdirectory name must be a `ParsedCommand` rawValue; every file other than
  `README.md` must end in `.txt`; a missing tree, an unknown directory, a non-`.txt` file,
  a real capture not in the versioned form, or a command without a positive fixture all
  FAIL the check.

## Scrub rules (R7, this repo is public)
- Serials → `XXXXXXXXXX`. UUIDs → `00000000-0000-0000-0000-000000000000`.
  `provisioning_UDID` → `00000000-0000000000000000`. JSON/plist syntax stays valid:
  values are replaced, never deleted.
- `/Users/<name>` → `/Users/user`. Time Machine `Name` → `Backup`,
  `MountPoint` → `/Volumes/Backup`. Any other volume name → `Volume`.
- "Part of macOS": an executable path that starts with `/System/`, `/usr/` (but not
  `/usr/local/`), `/bin/`, `/sbin/` or `/Library/Apple/`, or the name `kernel_task`.
  Everything else is `SomeApp`.
- `ps`: first 25 rows only. A non-macOS row's path becomes
  `/Applications/SomeApp.app/Contents/MacOS/SomeApp`.
- `top`: keep every line up to and including the `PID COMMAND MEM` header, plus the first
  25 process rows. A row's COMMAND stays only if its pid is a macOS process in the full,
  unscrubbed `ps` output taken just before; otherwise it becomes `SomeApp`, padded to the
  same column width.
- `pmset-assertions`: an owning process that is not part of macOS (pid looked up as for
  `top`) becomes `pid N(SomeApp)`. Its `named: "…"` becomes `named: "SomeApp assertion"`,
  and its `Details:` / `Localized=` text becomes `SomeApp` / `SOMEAPP`. Any `named:`
  string of a macOS process that carries personal content (a file, song, meeting, device
  or host name) is replaced the same way.
- Any other host name, computer name or user name in any capture becomes `server` /
  `Mac` / `user`.

## Captures with a fixed role
`pmset-assertions/pmset-assertions-macos27.0-caffeinate.txt` is read by name in
`Checks/WakeHoldersChecks.swift`, which asserts its exact assertions. Do not rename,
recapture or edit it.

## Provenance of `synthetic` files
- `sp-power/neg-localised-ru-synthetic.txt`: `system_profiler SPPowerDataType
  -AppleLanguages '(ru)'` did not produce localised (or any) output on this Mac/macOS
  version, so this file is the scrubbed English positive capture with its three labels
  replaced by the Russian ones (`Количество циклов:`, `Состояние:`,
  `Максимальная ёмкость:`), covering the localised-negative case from R3.

## Adding your own capture
Name the file per the naming law (get the version with `sw_vers -productVersion`) and
capture stdout only (`2>/dev/null`), as production parses only stdout. Run the exact
command for the directory you're adding to (from `ParsedCommand`):
- `ps`: `/bin/ps -axww -o pid=,rss=,time=,comm=`
- `top`: `/usr/bin/top -l 1 -stats pid,command,mem`
- `pmset-batt`: `/usr/bin/pmset -g batt`
- `pmset-custom`: `/usr/bin/pmset -g custom`
- `pmset-assertions`: `/usr/bin/pmset -g assertions`
- `sp-power`: `/usr/sbin/system_profiler SPPowerDataType`
- `sp-hardware`: `/usr/sbin/system_profiler -json SPHardwareDataType`
- `uptime`: `/usr/bin/uptime`
- `tmutil-destinationinfo`: `/usr/bin/tmutil destinationinfo -X`
- `diskutil-info`: `/usr/sbin/diskutil info -plist disk0`
- `smartctl`: `smartctl -A -j disk0` (path from `ReportCollector.findSmartctl()`)
- `fdesetup`: `/usr/bin/fdesetup status`
- `spctl`: `/usr/sbin/spctl --status`
- `csrutil`: `/usr/bin/csrutil status`
- `socketfilterfw`: `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`

Scrub per the rules above, drop the file in the command's directory, then run
`swift run MacDashboardChecks`.

The 8-line excerpt that lands in `mac_report.txt` on a parse failure is diagnostic
only: for structured or long outputs, ask the reporter for the full command output.
