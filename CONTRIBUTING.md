# Contributing

## Pull requests

Open PRs against `main`, the repository's default branch. `main` is protected:
nobody pushes to it directly, so every change — including the maintainer's —
arrives as a pull request.

## Build

```
./build_app.sh
```

Add `--install` to also move the built app into `~/Applications` (`dist.noindex/` is left empty):

```
./build_app.sh --install
```

If you rebuild often, run `tools/signing/make-identity.sh` once first. It creates a
local self-signed signing identity in your login keychain; `build_app.sh` then signs
with it, so macOS keeps the app's permissions (Full Disk Access, Automation) across
rebuilds. Without it the build is signed ad-hoc and prints a warning.

## Tests

```
swift test
```

This must stay green before you open a PR. It needs Xcode (the `Testing` module ships
with it, not with bare Command Line Tools).

Tests live in `Tests/MacDashboardTests/` and reach the app's code through
`@testable import MacDashboard`, so anything `internal` is testable; `private` and
`fileprivate` helpers are not, so put a helper you want covered in a non-private
declaration. Tests that touch process-wide state (the UI language, `UserDefaults`,
wall-clock timing) go inside the `.serialized` root suite `SerialTests`
(`TestSupport.swift`). Three opt-in probes: `MACDASH_LIVE=1 swift test --filter liveCanary`
runs every parsed command for real; `MACDASH_LIVE=1 swift test --filter ipswLiveCanary`
asks Apple's catalogue, ipsw.me and the Apple firmware CDN (a HEAD, no download) for
`iPhone18,2` and checks they still match `Tests/APIFixtures`; `MACDASH_SYSDIAGNOSE_ARCHIVE=<archive.tar.gz> swift
test --filter sysdiagnoseProbe` runs the sysdiagnose extractor on a real archive. No other
test uses the network.

## Code style

Code and comments: English only, regardless of UI language.

## Localization

Every new user-facing string needs an entry in both `StringsEN.swift` and
`StringsRU.swift`. No English-only UI text is accepted, since the app is bilingual and
switchable in Settings.

## A note on expectations

This app was built by someone who isn't a professional developer — a hobby project
written with Claude Code out of curiosity about their own Mac's health. Reviews and
responses to issues/PRs may be slow. Please be patient.
