#!/bin/zsh
# Builds "Clean My Claude.app" (release) and installs it in ~/Applications.
# Usage: ./scripts/build_app.sh [--no-install] [--zip]
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

EXEC="CleanMyClaude"
DISPLAY_NAME="Clean My Claude"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$DISPLAY_NAME.app"
VERSION="0.1.0"
INSTALL=1
ZIP=0
for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --zip) ZIP=1 ;;
  esac
done

echo "→ Compilation (release)…"
swift build -c release

echo "→ Vérification des garde-fous…"
"$ROOT/.build/release/$EXEC" --selftest

echo "→ Icône…"
ICON_WORK="$BUILD_DIR/icon"
rm -rf "$ICON_WORK"
mkdir -p "$ICON_WORK/AppIcon.iconset"
swift "$ROOT/scripts/make_icon.swift" "$ICON_WORK/icon-1024.png" >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON_WORK/icon-1024.png" --out "$ICON_WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$ICON_WORK/icon-1024.png" --out "$ICON_WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$ICON_WORK/AppIcon.icns"

echo "→ Assemblage de $DISPLAY_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp "$ICON_WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.olima34.cleanmyclaude</string>
  <key>CFBundleExecutable</key><string>$EXEC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>fr</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Clean My Claude demande au Finder de vider la Corbeille quand l'accès complet au disque n'est pas accordé.</string>
  <key>NSHumanReadableCopyright</key><string>Libre et gratuit — MIT</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on the Mac that built it.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

if [[ $ZIP -eq 1 ]]; then
  (cd "$BUILD_DIR" && rm -f CleanMyClaude.zip && ditto -c -k --keepParent "$DISPLAY_NAME.app" CleanMyClaude.zip)
  echo "✓ Archive : $BUILD_DIR/CleanMyClaude.zip"
fi

if [[ $INSTALL -eq 1 ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  rm -rf "$DEST/$DISPLAY_NAME.app"
  cp -R "$APP" "$DEST/"
  echo "✓ Installée dans $DEST/$DISPLAY_NAME.app"
else
  echo "✓ App prête : $APP"
fi
