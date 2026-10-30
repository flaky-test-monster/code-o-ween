#!/bin/bash
# Points every GitHub address in the README and the website at OWNER/NAME, so the project can
# be published under another account or repository name. The workflows need no change: they
# use whichever repository GitHub runs them in.
#
# Usage: ./set-repository.sh OWNER/NAME
#        ./set-repository.sh flaky-test-monster/code-o-ween

set -euo pipefail
unset CDPATH

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pattern='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
if [[ $# -ne 1 || ! "$1" =~ $pattern ]]; then
  printf 'Usage: %s OWNER/NAME\n' "$0" >&2
  exit 1
fi
owner="${1%%/*}"
name="${1#*/}"

for file in README.md docs/index.html; do
  path="$SCRIPT_DIR/$file"
  [[ -f "$path" ]] || continue
  tmp="$(mktemp "$path.XXXXXX")"
  # Repository links, the Pages address, and the --repo argument of gh attestation verify.
  sed -E \
    -e "s#github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#github.com/$owner/$name#g" \
    -e "s#[A-Za-z0-9-]+\.github\.io/[A-Za-z0-9._-]+#$owner.github.io/$name#g" \
    -e "s#--repo [A-Za-z0-9._-]+/[A-Za-z0-9._-]+#--repo $owner/$name#g" \
    "$path" >"$tmp"
  mv -f "$tmp" "$path"
done

printf 'Repository addresses now point at %s/%s:\n' "$owner" "$name"
grep -o -h -E "(github\.com/|[A-Za-z0-9-]+\.github\.io/)[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?" \
  "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/docs/index.html" 2>/dev/null | sort -u
