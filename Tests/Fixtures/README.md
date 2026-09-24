# Tests/Fixtures

Parser fixtures for R3-FIXTURES: one directory per `ParsedCommand` rawValue
(`Sources/MacDashboard/Engine/ParsedCommands.swift`), found by
`Checks/ParserFixtureChecks.swift` via `#filePath`, no Swift edit needed to add one.

## Naming law
- `<name>.txt` or `<name>-<variant>.txt` (no `neg-`/`synthetic` prefix/suffix) is a real
  capture (scrubbed) and must parse. `<variant>` describes the machine or state
  (`laptop`, `desktop`, `not-configured`, …).
- a name containing `synthetic` is hand-built and must parse. Its provenance is listed
  below.
- `neg-<what>.txt` must be rejected by the command's parser.
- every subdirectory name must be a `ParsedCommand` rawValue; every file other than
  `README.md` must end in `.txt`; a missing tree, an unknown directory, a non-`.txt`
  file or a command without a positive fixture all FAIL the check.

## Scrub rules (R7, this repo is public)
- Serials → `XXXXXXXXXX`. UUIDs → `00000000-0000-0000-0000-000000000000`.
  `provisioning_UDID` → `00000000-0000000000000000`. JSON/plist syntax stays valid:
  values are replaced, never deleted.
- `/Users/<name>` → `/Users/user`. Time Machine `Name` → `Backup`,
  `MountPoint` → `/Volumes/Backup`. Any other volume name → `Volume`.
- `ps`/`top`: first 25 rows only. Any process that is not part of macOS is renamed to
  `SomeApp` (and its `ps` path to `/Applications/SomeApp.app/Contents/MacOS/SomeApp`).

## Provenance of `synthetic` files
- `sp-power/neg-localised-ru-synthetic.txt`: `system_profiler SPPowerDataType
  -AppleLanguages '(ru)'` did not produce localised (or any) output on this Mac/macOS
  version, so this file is the scrubbed English positive capture with its three labels
  replaced by the Russian ones (`Количество циклов:`, `Состояние:`,
  `Максимальная ёмкость:`), covering the localised-negative case from R3.

## Adding your own capture
Run the exact command for the directory you're adding to (from `ParsedCommand`):
- `ps`: `/bin/ps -axww -o pid=,rss=,time=,comm=`
- `top`: `/usr/bin/top -l 1 -stats pid,command,mem`
- `pmset-batt`: `/usr/bin/pmset -g batt`
- `pmset-custom`: `/usr/bin/pmset -g custom`
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
