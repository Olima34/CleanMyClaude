#!/bin/bash
# Publishes an app already built for the checked-out commit as a version on the Releases page, with the commits since
# the previous version as notes. Run by the CI: .github/workflows/build.yml after every green push on main,
# release.yml for a vX.Y.Z tag pushed by hand. Needs GH_TOKEN.
# Usage: ./scripts/publish_release.sh 0.3.6 [build/CleanMyClaude.zip]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?numéro de version attendu, par exemple 0.3.6}"
ZIP="${2:-build/CleanMyClaude.zip}"
TAG="v$VERSION"
REPO="${GITHUB_REPOSITORY:-Olima34/CleanMyClaude}"
COMMIT="$(git rev-parse HEAD)"
# The previous version: the highest vX.Y.Z tag strictly before this commit.
PREVIOUS="$(git tag --merged HEAD --no-contains HEAD --list 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed -n 1p || true)"

NOTES="$(mktemp)"
{
  cat <<'NOTES'
**Installer en une ligne** (Terminal) :

```bash
curl -fsSL https://raw.githubusercontent.com/Olima34/CleanMyClaude/main/scripts/install.sh | bash
```

Ou télécharge **CleanMyClaude.zip** ci-dessous, glisse l'app dans Applications, puis au premier lancement :
Réglages Système › Confidentialité et sécurité › « Ouvrir quand même ». Déjà installée, l'app te propose elle-même cette version.

macOS 14 Sonoma ou plus récent, Apple Silicon et Intel.
NOTES
  if [[ -n "$PREVIOUS" ]]; then
    echo
    echo "## Ce qui change depuis la ${PREVIOUS#v}"
    echo
    git log --no-merges --format="- %s ([%h](https://github.com/$REPO/commit/%H))" "$PREVIOUS..HEAD"
  fi
} > "$NOTES"

# GitHub adds its own notes below (merged pull requests, link to the full comparison).
ARGS=(--target "$COMMIT" --title "Clean My Claude $VERSION" --notes-file "$NOTES" --generate-notes)
[[ -n "$PREVIOUS" ]] && ARGS+=(--notes-start-tag "$PREVIOUS")
gh release create "$TAG" "$ZIP" "${ARGS[@]}"
