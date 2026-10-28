#!/usr/bin/env bash
# PUBLIC-REPO-CLEANUP: keeps private material out of this public repo. Checks the PR
# title and body, every PR commit message, every added line and every added path for
# GENERIC leak patterns only: Claude session links and trailers, encoded home-folder
# project names, home-folder paths outside the fixture names, personal e-mail addresses.
# Also rejects an added top-level entry or tools/ entry that is not on the allowlists,
# so a non-app folder fails until someone adds it here on purpose.
# Matched text is never printed: Actions logs of a public repo are public.
# Every pattern below brackets one character, so this file passes its own check.
#
# Usage: public-hygiene.sh <base-sha> <head-sha>   (PR_TITLE, PR_BODY from the environment)
set -euo pipefail
base="$1" head="$2"

# Tracked top-level entries and tools/ entries (git ls-tree --name-only HEAD [tools/]).
TOP_ALLOW=".github .gitignore CHANGELOG.md CONTRIBUTING.md LICENSE MacDashboard.entitlements Package.swift README.md README.ru.md SECURITY.md SPEC.md Sources Tests build_app.sh docs tools"
TOOLS_ALLOW="bench-app.sh harness ls-prune.sh make_icon.swift perf signing visual"
# Fixture home-folder names used by tests (git grep -ohE over Sources/ Tests/ tools/).
USERS_ALLOW="Shared a fixture me test u user x"

P_SESSION='claude[.]ai/code'
P_TRAILER='claude-session[:]'
P_ENCODED='[-]users[-][a-z0-9._]+[-]'
P_HOME='/users/[a-z0-9._-]+'
P_EMAIL='[a-z0-9._%+-]+@[a-z][a-z0-9-]*([.][a-z0-9-]+)*[.][a-z]{2,}'
EMAIL_ALLOW='(@users[.]noreply[.]github[.]com|^noreply@github[.]com|^noreply@anthropic[.]com|^git@github[.]com|@example[.](com|org|net)|@updates[.]cdn-apple[.]com)$'

bad=0
report() { echo "::error::$2 in $1"; bad=1; }

# $1 = where (for the message); the text comes on stdin.
scan() {
  local where="$1" text n e
  text="$(cat)"
  [ -n "$text" ] || return 0
  if grep -qiE "$P_SESSION" <<<"$text"; then report "$where" "a Claude session link"; fi
  if grep -qiE "$P_TRAILER" <<<"$text"; then report "$where" "a Claude session trailer"; fi
  if grep -qiE "$P_ENCODED" <<<"$text"; then report "$where" "an encoded home-folder project name"; fi
  while IFS= read -r n; do
    case " $USERS_ALLOW " in *" $n "*) ;; *) report "$where" "a home-folder path outside the fixture names"; break ;; esac
  done < <(grep -oiE "$P_HOME" <<<"$text" | cut -d/ -f3 | sort -u || true)
  while IFS= read -r e; do
    if ! grep -qiE "$EMAIL_ALLOW" <<<"$e"; then report "$where" "an e-mail address that is not a noreply or example address"; break; fi
  done < <(grep -oiE "$P_EMAIL" <<<"$text" | sort -u || true)
  return 0
}

scan "the PR title or body" < <(printf '%s\n%s\n' "${PR_TITLE:-}" "${PR_BODY:-}")

for c in $(git rev-list "$base..$head"); do
  scan "the message of commit ${c:0:12}" < <(git log -1 --format=%B "$c")
done

while IFS= read -r f; do
  scan "the path of $f" <<<"$f"
  scan "the added lines of $f" < <(git diff -U0 --no-color "$base...$head" -- "$f" \
    | awk '/^\+\+\+ /{next} /^\+/{print substr($0, 2)}')
done < <(git diff --name-only --diff-filter=d "$base...$head")

while IFS= read -r f; do
  top="${f%%/*}"
  case " $TOP_ALLOW " in
    *" $top "*) ;;
    *) report "the PR" "a new top-level entry '$top' (not on TOP_ALLOW in .github/scripts/public-hygiene.sh)"; continue ;;
  esac
  if [ "$top" = tools ]; then
    rest="${f#tools/}"; sub="${rest%%/*}"
    case " $TOOLS_ALLOW " in
      *" $sub "*) ;;
      *) report "the PR" "a new tools/ entry '$sub' (not on TOOLS_ALLOW in .github/scripts/public-hygiene.sh)" ;;
    esac
  fi
done < <(git diff --name-only --diff-filter=AR "$base...$head")

[ "$bad" = 0 ] || exit 1
echo "public-hygiene: clean"
