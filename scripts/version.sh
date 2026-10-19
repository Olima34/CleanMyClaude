#!/bin/bash
# Prints the version number of the checked-out commit: the highest vX.Y.Z tag it contains, plus the commits since
# (v0.3.0 and 6 commits after it: 0.3.6). A local build and the version the CI publishes for the same commit thus carry
# the same number, even when the local clone has not fetched the tags the CI created since. Without any tag: 0.3.0.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="$(git tag --merged HEAD --list 'v[0-9]*' --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed -n 1p || true)"
if [[ "$TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  COUNT="$(git rev-list --count "$TAG..HEAD")"
  echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((10#${BASH_REMATCH[3]} + COUNT))"
else
  echo "0.3.0"
fi
