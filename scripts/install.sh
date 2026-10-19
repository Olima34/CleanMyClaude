#!/bin/bash
# Installs (or updates) Clean My Claude from the latest release, then opens it.
#   curl -fsSL https://raw.githubusercontent.com/Olima34/CleanMyClaude/main/scripts/install.sh | bash
set -euo pipefail

REPO="Olima34/CleanMyClaude"
APP="Clean My Claude.app"
BUNDLE_ID="io.github.olima34.cleanmyclaude"
URL="${CMC_ZIP_URL:-https://github.com/$REPO/releases/latest/download/CleanMyClaude.zip}"
# Tests: CMC_INSTALL_DIR installs elsewhere, without closing or opening the installed app.
TEST_DIR="${CMC_INSTALL_DIR:-}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Clean My Claude est une app pour Mac." >&2
  exit 1
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 14 )); then
  echo "Clean My Claude demande macOS 14 Sonoma ou plus récent (tu as $(sw_vers -productVersion))." >&2
  exit 1
fi

# Where it goes: where it already is (update), else Applications, else the Applications folder of the user.
if [[ -n "$TEST_DIR" ]]; then
  DEST="$TEST_DIR"
elif [[ -d "$HOME/Applications/$APP" ]]; then
  DEST="$HOME/Applications"
elif [[ -d "/Applications/$APP" || -w "/Applications" ]]; then
  DEST="/Applications"
else
  DEST="$HOME/Applications"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Téléchargement de Clean My Claude…"
curl -fL --progress-bar "$URL" -o "$TMP/CleanMyClaude.zip"
ditto -x -k "$TMP/CleanMyClaude.zip" "$TMP"
if [[ ! -d "$TMP/$APP" ]]; then
  echo "L'archive téléchargée ne contient pas l'app : réessaie dans un instant." >&2
  exit 1
fi

# An open copy is closed first (it reopens at the end).
if [[ -z "$TEST_DIR" ]]; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  sleep 1
fi

echo "→ Installation dans $DEST…"
mkdir -p "$DEST"
rm -rf "${DEST:?}/$APP"
ditto "$TMP/$APP" "$DEST/$APP"
# Downloaded by curl, the app carries no quarantine; this only matters if the archive did.
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

echo "✓ Clean My Claude est installé. Il s'ouvre ; ensuite, ⌥Espace ouvre le lanceur depuis n'importe où."
[[ -z "$TEST_DIR" ]] && open "$DEST/$APP"
exit 0
