#!/usr/bin/env bash
# RELEASE-FEATURE-GATING: a PR into a maintenance branch (release/X.Y) may carry only
#   - backports: `git cherry-pick -x` of a commit that is already on main, or
#   - release prep: commits touching only CHANGELOG.md, the notes template and the
#     VERSION=/CODENAME= lines of build_app.sh.
# Anything else (a branch cut from main, a fresh commit, a merge) would leak main's
# unreleased work into a patch release, so it fails the check.
# It guards against mistakes, not forgery: a backport is recognised by its -x trailer,
# and its content is not compared with the source commit, so conflict-resolved backports
# still pass. Reviewing the PR diff is the check on content.
#
# Usage: backport-only.sh <base-sha> <head-sha> <main-ref>
set -euo pipefail
base="$1" head="$2" main="$3"

is_release_prep() {
  local c="$1" files
  files="$(git diff-tree --no-commit-id --name-only -r "$c")"
  [ -n "$files" ] || return 1
  if printf '%s\n' "$files" | grep -vxE 'CHANGELOG\.md|\.github/RELEASE_NOTES_TEMPLATE\.md|build_app\.sh' >/dev/null; then
    return 1
  fi
  # build_app.sh, if touched: modified in place (no mode change, no delete) ...
  git diff --raw "$c^" "$c" -- build_app.sh \
    | awk '$1 != ":" $2 || $5 != "M" { bad = 1 } END { exit bad }' || return 1
  # ... and only its VERSION= and CODENAME= lines change. awk reads the whole diff
  # (no early exit, so no SIGPIPE under pipefail) and skips the file headers before
  # the first hunk, so a body line starting with "++"/"--" is still checked.
  git diff -U0 "$c^" "$c" -- build_app.sh \
    | awk 'p && /^[-+]/ && !/^[-+](VERSION|CODENAME)="[^"]*"$/ { bad = 1 }
           /^@@/ { p = 1 }
           END { exit bad }'
}

bad=0
if [ -n "$(git rev-list --merges "$base..$head")" ]; then
  echo "::error::merge commits are not allowed in a PR into a maintenance branch"
  bad=1
fi
for c in $(git rev-list --no-merges --reverse "$base..$head"); do
  src="$(git log -1 --format=%B "$c" \
    | sed -n 's/^(cherry picked from commit \([0-9a-f]\{40\}\))$/\1/p' | tail -1)"
  if [ -n "$src" ]; then
    if git merge-base --is-ancestor "$src" "$main" 2>/dev/null; then
      echo "ok   $c backport of $src"
    else
      echo "::error::$c is a cherry-pick of $src, which is not on main"
      bad=1
    fi
  elif is_release_prep "$c"; then
    echo "ok   $c release prep"
  else
    echo "::error::$c is neither a backport of a main commit (git cherry-pick -x) nor release prep"
    bad=1
  fi
done
exit "$bad"
