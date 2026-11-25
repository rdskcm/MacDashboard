# Moonport

A native macOS app (SwiftUI, Swift Package Manager, no third-party dependencies) that shows the health of this Mac. This file is for coding agents. People start with README.md and CONTRIBUTING.md.

## Build and test
- Build: `./build_app.sh`. Add `--install` to move the app into `~/Applications`. There is no Xcode project; the package builds from the command line.
- Tests: `swift test`. It needs Xcode, because the `Testing` module ships with it. It must be green before a pull request.
- CI fails on any build warning. `tools/check-warnings.sh` runs the same warnings-as-errors build locally.
- The opt-in live probes listed in CONTRIBUTING.md (for example `MACDASH_LIVE=1 swift test --filter liveCanary`) touch the real system or the network. No other test does.

## Rules
- This repository is public. Test fixtures, the visual fixture, screenshots and examples in the docs use only synthetic data: invented names, placeholder serials and IMEIs, fixture home folders such as `/Users/u`. Never a real person's name, a real device's identifiers or a real home-folder path. CI's `public-hygiene` check rejects the generic forms of these.
- Tests never read, move, delete or overwrite the app's real data folder `~/Library/Application Support/Moonport`. A test that needs a fresh start uses a temporary directory.
- Code, comments and commit messages are English only. Every user-facing string is a key in `Sources/Moonport/Engine/Strings/Strings+<Feature>.swift` with an English and a Russian value (see CONTRIBUTING.md > Localization).
- `main` is protected: every change arrives as a pull request from its own branch.
- `AGENTS.md` is generated from this file by `tools/agent-config/agent_config.py`. Edit `CLAUDE.md`, run `python3 -I tools/agent-config/agent_config.py --root .`, and commit both files. CI fails when they disagree.
