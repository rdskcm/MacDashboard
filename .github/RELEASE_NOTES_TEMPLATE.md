# Release notes template

Every MacDashboard release on GitHub follows this file. Release flow: the tag push runs
`.github/workflows/release.yml`, which creates the release with the standard title and a placeholder
note and uploads `MacDashboard.zip`. Then write the body below into a file and apply it:

    gh release edit vX.Y -R rdskcm/MacDashboard --title "vX.Y (Codename)" --notes-file <body file>

Edit title and body only. Never touch the tag or the asset.

## Title

`vX.Y (Codename)` — for example `v2.2 (Krieg)`. Patch releases: `vX.Y.Z (Codename)`. Nothing before or
after it. Codenames name a major version: 1.x = Cadia, 2.x = Krieg (`CODENAME` in `build_app.sh`).

## Body — sections in this order; leave out any that would be empty

1. App line — this exact line in every release:
   `MacDashboard is a native macOS app that checks your Mac: a full system report at launch, live metrics, a local history of past reports, and one-click maintenance, in English or Russian.`
2. One sentence: the main point of this version. Starts with `Version X.Y`.
3. `### New`, `### Improved`, `### Fixed` — one bullet per item.
   - New: something the app did not do before.
   - Improved: something it did before and now does better.
   - Fixed: something that was wrong and now works.
   - The first release lists what the app shipped with under New.
4. `### Before you update` — only actions the user must take before or after updating. No general news.
5. `### Requirements` — two bullets:
   - `macOS <N> (<name>) or later` — the minimum from `build_app.sh` `MIN_MACOS` / the asset's `LSMinimumSystemVersion`.
   - Chip: `Apple Silicon or Intel (universal build)` for v1.0–v2.1; `Apple Silicon only` from v2.2 on.
6. `### Install` — this block, with the release's SHA-256 (from the workflow run summary, or
   `shasum -a 256 MacDashboard.zip` on the uploaded asset):

       Download `MacDashboard.zip` below, unzip it, and move `MacDashboard.app` to Applications. The app is ad-hoc signed but not notarized (no Apple Developer certificate yet), so macOS blocks it on first launch. Allow it once, either way:

       - **System Settings → Privacy & Security → Open Anyway** (the old right-click → Open no longer works on macOS 15 and later).
       - **Or in Terminal:** `xattr -dr com.apple.quarantine /Applications/MacDashboard.app`

       SHA-256 of `MacDashboard.zip`: `<sha256>`

       Step by step, and building from source: [README](https://github.com/rdskcm/MacDashboard#install).

7. `### Privacy` — this exact paragraph:

       The app makes no telemetry or analytics calls of any kind. The only network activity is `softwareupdate -l` when a report is collected (to check for pending macOS updates) and, if you explicitly click an upgrade/install action, Homebrew's own downloads. The optional AI assistant feature is not compiled into the default build.

8. Footer, no heading:

       Full list and known limitations: [CHANGELOG.md](https://github.com/rdskcm/MacDashboard/blob/main/CHANGELOG.md). All code changes since vP: [vP...vX.Y](https://github.com/rdskcm/MacDashboard/compare/vP...vX.Y).

       Licensed under the MIT License.

   `vP` is the previous release tag. The first release has no compare link.

## What goes in the release body

Only items that change something for a person who downloads `MacDashboard.zip`. Items for people who build
from source or contribute go in CHANGELOG.md only. Every body bullet must have a matching item in the same
version's CHANGELOG entry, under the same heading.

## Style

- Plain, direct English. Short sentences, common words.
- Each bullet is one line: what changed, from the user's side. Concise but specific (name the screen, the
  reading, the number).
- No metaphors, no marketing words, no "we" / "our". Say "now does X", not "brings", "delivers", "unlocks".
- Bullet length: 200 characters at most.
- Banned words: seamless, robust, leverage, powerful, effortless, delight, blazing, revamp, supercharge,
  under the hood, game-changing, cutting-edge, stunning, beautiful, honest.
- English only.

## CHANGELOG.md entry shape

    ## [X.Y] (Codename) - YYYY-MM-DD

    <one or two sentences: the main point of this version>

    ### New
    ### Improved
    ### Fixed
    ### Before you update
    ### Known limitations        (only when there are any)

The CHANGELOG entry may give more detail per item than the release body; it is the full list.
