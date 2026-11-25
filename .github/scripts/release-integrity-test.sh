#!/usr/bin/env bash
# RELEASE-INTEGRITY: fixture cases for release-gate.sh and find-xcode.sh. No network and
# no GitHub writes: a stub `gh` on PATH prints canned `gh api --jq` output, and fake Xcode
# bundles live in a temporary directory. Run from anywhere on a Mac:
#   .github/scripts/release-integrity-test.sh
# Two cases (API error, unknown tag) wait out release-gate.sh's retries, about 10 s each.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
gate="$here/release-gate.sh"
findx="$here/find-xcode.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin" "$tmp/fx"
# Stub gh: the endpoint (first argument after `api` and `--paginate`), query dropped and
# "/" turned into "_", names the fixture file to print. A FAIL file fails every call.
cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
ep=""
for a in "$@"; do
  case "$a" in api|--paginate) continue ;; esac
  ep="$a"; break
done
if [ -e "$GATE_FIXTURE/FAIL" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
f="$GATE_FIXTURE/$(printf '%s' "${ep%%\?*}" | tr '/' '_')"
if [ ! -f "$f" ]; then echo "HTTP 404: Not Found ($ep)" >&2; exit 1; fi
cat "$f"
STUB
chmod +x "$tmp/bin/gh"

R="o/r"
S="1111111111111111111111111111111111111111"
M="2222222222222222222222222222222222222222"
L="3333333333333333333333333333333333333333"
pass=0
fail=0

# put <case> <fixture-file> <content>
put() { mkdir -p "$tmp/fx/$1"; printf '%s\n' "$3" >"$tmp/fx/$1/$2"; }

# run_case <name> <expected-exit> <pattern the output must contain, or -> <command...>
run_case() {
  local name="$1" want="$2" pat="$3" got=0
  shift 3
  "$@" >"$tmp/$name.out" 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"; sed 's/^/    /' "$tmp/$name.out"; fail=$((fail + 1))
  elif [ "$pat" != "-" ] && ! grep -q -- "$pat" "$tmp/$name.out"; then
    echo "FAIL $name: output lacks '$pat'"; sed 's/^/    /' "$tmp/$name.out"; fail=$((fail + 1))
  else
    echo "PASS $name (exit $got)"; pass=$((pass + 1))
  fi
}

# gate_case <name> <expected-exit> <pattern|-> <check> <tag-or-sha>
gate_case() {
  mkdir -p "$tmp/fx/$1"
  run_case "$1" "$2" "$3" env "GATE_FIXTURE=$tmp/fx/$1" "PATH=$tmp/bin:$PATH" "$gate" "$4" "$R" "$5"
}

RUNS="repos_o_r_actions_workflows_ci.yml_runs"
MAIN="repos_o_r_git_ref_heads_main"
REL="repos_o_r_git_matching-refs_heads_release_"
RELS="repos_o_r_releases"
jobs_of() { echo "repos_o_r_actions_runs_$1_jobs"; }
cmp_of() { echo "repos_o_r_compare_$1...$S"; }

# --- ci-passed
put ci-ok "$RUNS" "101 completed success main"
put ci-ok "$(jobs_of 101)" "success"
gate_case ci-ok 0 "OK — build-and-check succeeded" ci-passed "$S"

put ci-missing "$RUNS" ""
gate_case ci-missing 1 "no push-event run of ci.yml exists" ci-passed "$S"

put ci-failed "$RUNS" "102 completed failure main"
gate_case ci-failed 1 "has a successful build-and-check job" ci-passed "$S"

put ci-running "$RUNS" "103 in_progress none main"
gate_case ci-running 1 "in_progress" ci-passed "$S"

put ci-job-missing "$RUNS" "104 completed success main"
put ci-job-missing "$(jobs_of 104)" ""
gate_case ci-job-missing 1 "no such job" ci-passed "$S"

put ci-second-run "$RUNS" "105 completed failure release/2.3
106 completed success main"
put ci-second-run "$(jobs_of 106)" "success"
gate_case ci-second-run 0 "push-event run 106" ci-passed "$S"

put ci-api-error FAIL "x"
gate_case ci-api-error 2 "after 3 attempts" ci-passed "$S"

# --- on-release-line
put line-main "$MAIN" "refs/heads/main $M"
put line-main "$REL" "refs/heads/release/2.3 $L"
put line-main "$(cmp_of "$M")" "behind"
gate_case line-main 0 "is on main" on-release-line "$S"

put line-release "$MAIN" "refs/heads/main $M"
put line-release "$REL" "refs/heads/release/2.3 $L"
put line-release "$(cmp_of "$M")" "diverged"
put line-release "$(cmp_of "$L")" "identical"
gate_case line-release 0 "is on release/2.3" on-release-line "$S"

put line-none "$MAIN" "refs/heads/main $M"
put line-none "$REL" "refs/heads/release/2.3 $L"
put line-none "$(cmp_of "$M")" "diverged"
put line-none "$(cmp_of "$L")" "ahead"
gate_case line-none 1 "is not on main" on-release-line "$S"

put line-no-branches "$MAIN" "refs/heads/main $M"
put line-no-branches "$REL" ""
put line-no-branches "$(cmp_of "$M")" "ahead"
gate_case line-no-branches 1 "is not on main" on-release-line "$S"

# --- no-release
put rel-absent "$RELS" "$(printf 'v2.3.3\tfalse\thttps://example.com/r/1')"
gate_case rel-absent 0 "OK — no release or draft exists" no-release v9.9.9

put rel-none "$RELS" ""
gate_case rel-none 0 "OK — no release or draft exists" no-release v9.9.9

put rel-draft "$RELS" "$(printf 'v2.3.3\tfalse\thttps://example.com/r/1\nv9.9.9\ttrue\thttps://example.com/r/2')"
gate_case rel-draft 1 "a draft release for v9.9.9 already exists" no-release v9.9.9

put rel-published "$RELS" "$(printf 'v9.9.9\tfalse\thttps://example.com/r/3')"
gate_case rel-published 1 "already published" no-release v9.9.9

# --- resolve
put resolve-ok "repos_o_r_commits_tags_v9.9.9" "$S"
gate_case resolve-ok 0 "^$S\$" resolve v9.9.9

gate_case resolve-missing 2 "after 3 attempts" resolve v9.9.9

# --- argument checks
gate_case arg-short-sha 2 "40-character" ci-passed abc123
gate_case arg-bad-tag 2 "expected a release tag" no-release 'v1;rm'

# --- find-xcode.sh
fake_xcode() {  # fake_xcode <apps-dir> <bundle name> <CFBundleShortVersionString>
  mkdir -p "$1/$2/Contents"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $3" "$1/$2/Contents/Info.plist" >/dev/null
}
A="$tmp/apps"
fake_xcode "$A" Xcode_26.5.app 26.5
fake_xcode "$A" Xcode_26.6.0.app 26.6
fake_xcode "$A" Xcode_26.7_beta.app 26.7
fake_xcode "$A" Xcode_26.8_RC.app 26.8
mkdir -p "$tmp/empty"
run_case xcode-found 0 "^$A/Xcode_26.6.0.app\$" "$findx" 26.6 "$A"
run_case xcode-normalised 0 "^$A/Xcode_26.6.0.app\$" "$findx" 26.6.0 "$A"
run_case xcode-missing 1 "bump the pin" "$findx" 26.9 "$A"
run_case xcode-beta-only 1 "bump the pin" "$findx" 26.7 "$A"
run_case xcode-rc-only 1 "bump the pin" "$findx" 26.8 "$A"
run_case xcode-empty-dir 1 "bump the pin" "$findx" 26.6 "$tmp/empty"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
