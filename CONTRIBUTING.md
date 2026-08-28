# Contributing

## Pull requests

Open PRs against `main`, the repository's default branch. `main` is protected:
nobody pushes to it directly, so every change — including the maintainer's —
arrives as a pull request.

## Build

```
./build_app.sh
```

Add `--install` to also copy the built app into `~/Applications`:

```
./build_app.sh --install
```

## Checks

```
swift run MacDashboardChecks
```

This must stay green before you open a PR.

## The two-target symlink trap

`MacDashboardChecks` is a separate SwiftPM executable target that runs the pure-logic
("Engine") files under `Sources/MacDashboard/Engine/` as a plain assert-and-print check
harness. Most files in `Checks/` are symlinks back into `Sources/MacDashboard/Engine/`,
not real copies — see `Checks/README.md` for the exact mechanics. `Views/` files and
`DashboardModel.swift` are app-only (SwiftUI / `@Observable`) and are never symlinked
in. Practical consequence: if you add logic that both the app and `MacDashboardChecks`
need to exercise, put it in a file that lives in (or gets symlinked into) `Checks/` —
not in `Views/`, or the checks target simply won't see it.

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
