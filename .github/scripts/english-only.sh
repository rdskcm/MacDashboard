#!/usr/bin/env bash
# ENGLISH-DEFAULT: PR title, PR body and every PR commit message are English. Rejects any Cyrillic letter
# (U+0400-U+04FF). Matched text is never printed: Actions logs of a public repo are public.
# Usage: english-only.sh <base-sha> <head-sha>   (PR_TITLE, PR_BODY from the environment)
set -euo pipefail
base="$1" head="$2"
bad=0
check() { if perl -CS -0777 -ne 'exit(/[\x{0400}-\x{04FF}]/ ? 0 : 1)' <<<"$2"; then echo "::error::Cyrillic text in $1 (write it in English; see CONTRIBUTING.md > Code style)"; bad=1; fi; }
check "the PR title or body" "$(printf '%s\n%s\n' "${PR_TITLE:-}" "${PR_BODY:-}")"
for c in $(git rev-list "$base..$head"); do
  check "the message of commit ${c:0:12}" "$(git log -1 --format=%B "$c")"
done
[ "$bad" = 0 ] || exit 1
echo "english-only: clean"
