#!/usr/bin/env bash
# Diffs two directories of rendered manifests (see validate-manifests.sh) and
# writes a PR-comment-sized markdown report.
#
# Usage: diff-manifests.sh <base-dir> <target-dir> <output.md>
set -uo pipefail

BASE="$1"
TARGET="$2"
OUT="$3"
# GitHub comments are capped at 65536 chars; leave room for the wrapper text
MAX_CHARS=60000

# Strip the directory prefixes and timestamps from the diff headers
diff="$(diff -ruN "$BASE" "$TARGET" | sed -E \
  -e 's#^diff -ruN [^ ]*/([^ /]+) .*#diff \1#' \
  -e 's#^(---|\+\+\+) [^/]+/([^[:space:]]+).*#\1 \2#')"

{
  echo "## Rendered manifest diff"
  echo
  if [ -z "$diff" ]; then
    echo "No changes to the rendered Helm charts."
  else
    files=$(echo "$diff" | grep -c '^diff ')
    echo "$files rendered chart(s) changed."
    echo
    echo '```diff'
    if [ "${#diff}" -gt "$MAX_CHARS" ]; then
      echo "${diff:0:$MAX_CHARS}"
      echo
      echo "... diff truncated, see the workflow logs for the full output"
    else
      echo "$diff"
    fi
    echo '```'
  fi
} >"$OUT"
