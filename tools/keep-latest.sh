#!/bin/bash
# tools/keep-latest.sh — run-output retention (NIGHT-STANDING-JOBS): in PARENT, keeps the KEEP newest directories whose
# name matches the extended regex REGEX and deletes the older ones, except a directory a night job still names.
# Newest = last in name order: every name a caller passes starts with a YYYYMMDD stamp or date.
#
# Usage: tools/keep-latest.sh [--dry-run] [--exclude DIR] PARENT REGEX KEEP
#   PARENT     absolute directory inside tools/perf/out or tools/visual/out of this checkout (anything else: exit 64)
#   REGEX      extended regex for the directory name, anchored by the caller, e.g. '^[0-9]{8}-[0-9]{6}$'
#   KEEP       1-99
#   --dry-run  deletes nothing
#   --exclude DIR  the caller's run in progress: a directory whose physical path (pwd -P) equals DIR's is never deleted,
#              whatever its name. It still counts toward KEEP.
# Protected: a directory whose path occurs in a queued night job (<night>/queue/*.job) or in a standing job's last
#   result (<night>/standing/last-*); <night> = $NIGHT_OUT when it is absolute, else tools/perf/out/night.noindex.
#   Paths are compared as written and by physical path (/private/tmp = /tmp). Symbolic links are never followed, counted or deleted.
# Output (tab-separated, one line per directory acted on): "pruned	<path>" | "kept	<path>	named by <file>" |
#   "would prune	<path>	<KB>"; nothing when there is nothing to prune. A failed delete: "prune failed	<path>" on stderr.
# Exit: 0 | 64 usage or refused PARENT. Callers ignore the exit status.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { sed -n '2,/^set -uo/{/^#/p;}' "$0" | sed 's/^# \{0,1\}//'; }
DRY=0; EXCL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --exclude) [ $# -ge 2 ] || { usage >&2; exit 64; }
      EXCL="$(cd "$2" 2>/dev/null && pwd -P)" || EXCL=""; shift 2 ;;
    *) break ;;
  esac
done
[ $# -eq 3 ] || { usage >&2; exit 64; }
PARENT="${1%/}"; RE="$2"; KEEP="$3"
{ [[ "$KEEP" =~ ^[0-9]{1,2}$ ]] && [ "$((10#$KEEP))" -ge 1 ]; } || { echo "keep-latest: KEEP must be 1-99" >&2; exit 64; }
KEEP=$((10#$KEEP))
case "$PARENT" in /*) ;; *) echo "keep-latest: PARENT must be an absolute path" >&2; exit 64 ;; esac
[ -n "$RE" ] || { echo "keep-latest: REGEX is empty" >&2; exit 64; }
[ -d "$PARENT" ] || exit 0
REAL="$(cd "$PARENT" && pwd -P)" || exit 64
RROOT="$(cd "$ROOT" && pwd -P)"
case "$REAL/" in
  "$RROOT/tools/perf/out/"*|"$RROOT/tools/visual/out/"*) ;;
  *) echo "keep-latest: refused: $PARENT is not inside tools/perf/out or tools/visual/out of $ROOT" >&2; exit 64 ;;
esac

NIGHT="$ROOT/tools/perf/out/night.noindex"
case "${NIGHT_OUT:-}" in /*) NIGHT="${NIGHT_OUT%/}" ;; esac
PROT=()
for f in "$NIGHT"/queue/*.job "$NIGHT"/standing/last-*; do [ -f "$f" ] && PROT+=("$f"); done

# Physical paths of every existing absolute path a protecting file mentions: "<physical path><TAB><file>"
NAMED=""
if [ "${#PROT[@]}" != 0 ]; then
  while IFS=$'\t' read -r f t; do
    [ -e "$t" ] || continue
    if [ -d "$t" ]; then q="$(cd "$t" && pwd -P)"; else q="$(cd "$(dirname "$t")" && pwd -P)/$(basename "$t")"; fi
    NAMED+="$q"$'\t'"$f"$'\n'
  done < <(for f in "${PROT[@]}"; do grep -oE '/[^[:space:]"'"'"':=,;()]+' "$f" 2>/dev/null | sed "s|^|$f	|"; done)
fi

n=0
while IFS= read -r b; do
  [[ "$b" =~ $RE ]] || continue
  p="$PARENT/$b"
  { [ -d "$p" ] && [ ! -L "$p" ]; } || continue
  n=$((n + 1)); [ "$n" -le "$KEEP" ] && continue
  cp="$(cd "$p" && pwd -P)"
  [ -n "$EXCL" ] && [ "$cp" = "$EXCL" ] && continue
  by=""
  [ "${#PROT[@]}" = 0 ] || by="$(grep -lF -- "$p" "${PROT[@]}" 2>/dev/null | head -1)"
  if [ -z "$by" ] && [ -n "$NAMED" ]; then
    while IFS=$'\t' read -r q f; do
      [ -n "$q" ] || continue
      case "$q/" in "$cp/"*) by="$f"; break ;; esac
    done <<< "$NAMED"
  fi
  if [ -n "$by" ]; then printf 'kept\t%s\tnamed by %s\n' "$p" "$by"; continue; fi
  if [ "$DRY" = 1 ]; then printf 'would prune\t%s\t%s\n' "$p" "$(du -sk "$p" 2>/dev/null | awk '{print $1}')"; continue; fi
  if rm -rf -- "$p"; then printf 'pruned\t%s\n' "$p"; else printf 'prune failed\t%s\n' "$p" >&2; fi
done < <(ls -1 "$PARENT" | LC_ALL=C sort -r)
exit 0
