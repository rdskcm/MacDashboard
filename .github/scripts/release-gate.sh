#!/usr/bin/env bash
# RELEASE-INTEGRITY: the checks Release runs before it builds and before it creates the
# draft. They live here, not inline in release.yml, so they can be run on a Mac against
# real commits with an authenticated `gh`. Every call is a read-only `gh api` GET.
#
# Usage: release-gate.sh <check> <owner/repo> <tag-or-sha>
#   resolve         <tag>  print the commit the tag points to (annotated tags peeled)
#   on-release-line <sha>  the commit is reachable from main or from a release/* branch
#   ci-passed       <sha>  a push-event run of ci.yml on exactly this commit concluded
#                          success and its build-and-check job succeeded
#   no-release      <tag>  no release, draft or published, exists for the tag. Drafts are
#                          listed only to a token with push access, so Release runs this
#                          in its contents: write job.
# Exit codes: 0 the check passed, 1 the check refused, 2 bad arguments or a GitHub API
# error. Nothing waits for CI: missing, running or failed CI is a refusal, and Release is
# re-run once CI on the commit has succeeded. Fixture cases: release-integrity-test.sh.
set -euo pipefail

CI_WORKFLOW="ci.yml"
CI_JOB="build-and-check"

err() { echo "::error::$1" >&2; }

usage() {
  err "usage: release-gate.sh resolve|on-release-line|ci-passed|no-release <owner/repo> <tag-or-sha>"
  exit 2
}

# `gh api` GET with three attempts 5 s apart: the API has returned transient EOFs. stdin
# is closed so gh never reads the caller's here-strings. Exits 2 when all attempts fail.
# With --not-found-ok first, an HTTP 404 returns 4 at once (no retry, no message) for the caller to handle.
api() {
  local errf out attempt nf=0
  if [ "${1:-}" = "--not-found-ok" ]; then nf=1; shift; fi
  errf="$(mktemp)"
  for attempt in 1 2 3; do
    if out="$(gh api "$@" </dev/null 2>"$errf")"; then
      rm -f "$errf"
      if [ -n "$out" ]; then printf '%s\n' "$out"; fi
      return 0
    fi
    if [ "$nf" = 1 ] && grep -q 'HTTP 404' "$errf"; then rm -f "$errf"; return 4; fi
    if [ "$attempt" -lt 3 ]; then sleep 5; fi
  done
  err "GitHub API call failed after 3 attempts: gh api $* -> $(tr '\n' ' ' <"$errf")"
  rm -f "$errf"
  exit 2
}

cmd_resolve() {
  local sha
  sha="$(api "repos/$repo/commits/tags/$arg" --jq '.sha')"
  if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    err "tag $arg did not resolve to a commit (got '$sha')"
    exit 2
  fi
  echo "$sha"
}

cmd_on_release_line() {
  local refs rel ref tip status rc
  refs="$(api "repos/$repo/git/ref/heads/main" --jq '"\(.ref) \(.object.sha)"')"
  rel="$(api --paginate "repos/$repo/git/matching-refs/heads/release/" --jq '.[] | "\(.ref) \(.object.sha)"')"
  if [ -n "$rel" ]; then refs="$refs"$'\n'"$rel"; fi
  echo "is $arg on main or a release/* branch?"
  while read -r ref tip; do
    rc=0; status="$(api --not-found-ok "repos/$repo/compare/$tip...$arg?per_page=1" --jq '.status')" || rc=$?
    if [ "$rc" = 4 ]; then
      err "$arg is not a commit of $repo (GitHub answered 404 for the compare). A release is cut only from a commit on main or a release/* branch."
      exit 1
    fi
    [ "$rc" = 0 ] || exit "$rc"
    echo "  ${ref#refs/heads/} at $tip: $status"
    case "$status" in
      identical|behind) echo "OK — $arg is on ${ref#refs/heads/}"; return 0 ;;
    esac
  done <<<"$refs"
  err "$arg is not on main or on any release/* branch. A release is cut only from a commit on one of them."
  exit 1
}

cmd_ci_passed() {
  local runs id status conclusion branch jobs ok=""
  runs="$(api "repos/$repo/actions/workflows/$CI_WORKFLOW/runs?head_sha=$arg&event=push&per_page=100" \
    --jq '.workflow_runs[] | "\(.id) \(.status) \(.conclusion // "none") \(.head_branch)"')"
  if [ -z "$runs" ]; then
    err "no push-event run of $CI_WORKFLOW exists for $arg. CI runs on push only on main and release/*, after a merge. Tag only after that run has succeeded, then re-run Release from the tag."
    exit 1
  fi
  echo "push-event $CI_WORKFLOW runs on $arg:"
  while read -r id status conclusion branch; do
    echo "  run $id on $branch: $status, $conclusion"
    if [ "$conclusion" != "success" ]; then continue; fi
    jobs="$(api "repos/$repo/actions/runs/$id/jobs?filter=latest&per_page=100" \
      --jq ".jobs[] | select(.name == \"$CI_JOB\") | .conclusion // \"none\"")"
    if grep -qx 'success' <<<"$jobs"; then ok="$id"; break; fi
    echo "    run $id has no successful $CI_JOB job (got: ${jobs:-no such job})"
  done <<<"$runs"
  if [ -z "$ok" ]; then
    err "no push-event run of $CI_WORKFLOW on $arg has a successful $CI_JOB job (see the runs above). Nothing waits here: once CI on this commit has succeeded (re-run it if it failed or was cancelled), re-run Release from the tag."
    exit 1
  fi
  echo "OK — $CI_JOB succeeded in push-event run $ok on $arg"
}

cmd_no_release() {
  local rows tag_name draft url
  rows="$(api --paginate "repos/$repo/releases?per_page=100" --jq '.[] | "\(.tag_name)\t\(.draft)\t\(.html_url)"')"
  while IFS=$'\t' read -r tag_name draft url; do
    if [ "$tag_name" != "$arg" ]; then continue; fi
    if [ "$draft" = "true" ]; then
      err "a draft release for $arg already exists ($url). Assets are never replaced. If the draft is bad, delete it by hand (gh release delete $arg), then re-run Release from the tag."
    else
      err "release $arg is already published ($url). A published release is never changed. Fix a broken build with the next patch number."
    fi
    exit 1
  done <<<"$rows"
  echo "OK — no release or draft exists for $arg"
}

[ "$#" -eq 3 ] || usage
check="$1" repo="$2" arg="$3"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
case "$check" in
  resolve|no-release)
    [[ "$arg" =~ ^v[0-9A-Za-z._-]+$ ]] || { err "expected a release tag like v3.0, got '$arg'"; exit 2; } ;;
  on-release-line|ci-passed)
    [[ "$arg" =~ ^[0-9a-f]{40}$ ]] || { err "expected a 40-character commit SHA, got '$arg'"; exit 2; } ;;
  *) usage ;;
esac
case "$check" in
  resolve) cmd_resolve ;;
  on-release-line) cmd_on_release_line ;;
  ci-passed) cmd_ci_passed ;;
  no-release) cmd_no_release ;;
esac
