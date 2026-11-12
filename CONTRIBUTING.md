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

CI also fails on any build warning in the app or the tests. `tools/check-warnings.sh`
runs the same check on your Mac: a clean debug build of both, with warnings as errors.

Tests live in `Tests/MoonportTests/` and reach the app's code through
`@testable import Moonport`, so anything `internal` is testable; `private` and
`fileprivate` helpers are not, so put a helper you want covered in a non-private
declaration. Tests that touch process-wide state (the UI language, `UserDefaults`,
wall-clock timing) go inside the `.serialized` root suite `SerialTests`
(`TestSupport.swift`). Tests start in English (`SerialTests` pins `.en`); a test that asserts Russian output through the global `L` puts `@Suite(.uiLanguage(.ru))` on its struct or compares against `StringsRU()`. Three opt-in probes: `MACDASH_LIVE=1 swift test --filter liveCanary`
runs every parsed command for real; `MACDASH_LIVE=1 swift test --filter ipswLiveCanary`
asks Apple's catalogue, ipsw.me and the Apple firmware CDN (a HEAD, no download) for
`iPhone18,2` and checks they still match `Tests/APIFixtures`; `MACDASH_SYSDIAGNOSE_ARCHIVE=<archive.tar.gz> swift
test --filter sysdiagnoseProbe` runs the sysdiagnose extractor on a real archive. No other
test uses the network.

## Fixture and demo data

Test fixtures, the visual fixture, screenshots and examples in the docs use only
synthetic data: invented names («Alex», «Sam»), placeholder serials and IMEIs,
fixture home folders such as `/Users/u`. Never a real person's name, a real device's
identifiers or a real home-folder path. The `public-hygiene` check on every pull
request rejects the generic forms of these.

## Code style

Code, comments and commit messages: English only, regardless of UI language. A fix to Russian text is described in English, subject prefix `Russian localization:` (for example `Russian localization: fix the plural of snapshot in the Backups card`). CI (`english-only`) rejects Cyrillic in a PR title, body or commit message; `EnglishFirstTests` rejects it in comments.

## Localization

Every user-facing string is a key in one feature file under
`Sources/Moonport/Engine/Strings/` (`Strings+<Feature>.swift`). Each file holds the
feature's protocol, the English table (`extension StringsEN`, the reference) and the
Russian table (`extension StringsRU`, the translation); a new key goes into all three
parts of the same file, and a key missing from either table does not compile. No
English-only UI text is accepted, since the app is bilingual and switchable in Settings.

Write the English value first; the Russian value is its translation and sits in the same file. English is the reference and the fallback for any language added later (`LanguageChoice.resolve` maps an unknown system language to English). Russian grammar helpers (`ruPlural`, the attention number words) live next to the Russian tables.

## A note on expectations

This app was built by someone who isn't a professional developer — a hobby project
written with Claude Code out of curiosity about their own Mac's health. Reviews and
responses to issues/PRs may be slow. Please be patient.
