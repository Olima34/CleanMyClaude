#!/bin/zsh
# Builds "Clean My Claude.app" (release) and installs it in ~/Applications.
# Usage: ./scripts/build_app.sh [--no-install] [--zip] [--universal]
#   --universal : Apple Silicon et Intel dans la même app (pour les versions publiées).
#   CMC_VERSION=0.3.0 : numéro de version (sinon celui ci-dessous).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

EXEC="CleanMyClaude"
DISPLAY_NAME="Clean My Claude"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$DISPLAY_NAME.app"
VERSION="${CMC_VERSION:-0.3.0}"
INSTALL=1
ZIP=0
UNIVERSAL=0
for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --zip) ZIP=1 ;;
    --universal) UNIVERSAL=1 ;;
  esac
done

echo "→ Compilation (release)…"
ARCHS=()
[[ $UNIVERSAL -eq 1 ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/$EXEC"

echo "→ Vérification des garde-fous…"
"$BIN" --selftest
"$BIN" --selftest --demo

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
cp "$BIN" "$APP/Contents/MacOS/$EXEC"
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
  <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
  <key>CFBundleAllowMixedLocalizations</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Clean My Claude pilote le Finder et Événements système pour vider la Corbeille, basculer le mode sombre, redémarrer ou éteindre, uniquement quand tu le demandes.</string>
  <key>NSLocationUsageDescription</key><string>macOS n'indique le nom du réseau Wi-Fi qu'aux apps autorisées à utiliser la localisation. Ta position n'est ni lue ni enregistrée.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>macOS n'indique le nom du réseau Wi-Fi qu'aux apps autorisées à utiliser la localisation. Ta position n'est ni lue ni enregistrée.</string>
  <key>NSLocalNetworkUsageDescription</key><string>Pour mesurer la latence de ta box et des appareils de ton réseau, à ta demande.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Pour mesurer, ranger ou convertir les fichiers de ton Bureau, à ta demande.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Pour mesurer, ranger ou convertir tes documents, à ta demande.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Pour repérer les installeurs oubliés et ranger tes téléchargements, à ta demande.</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Convertir avec Clean My Claude</string></dict>
      <key>NSMessage</key><string>convertFiles</string>
      <key>NSPortName</key><string>$DISPLAY_NAME</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
    </dict>
  </array>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>io.github.olima34.cleanmyclaude</string>
      <key>CFBundleURLSchemes</key><array><string>cleanmyclaude</string></array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Fichier à convertir</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.item</string></array>
    </dict>
  </array>
  <key>NSHumanReadableCopyright</key><string>Libre et gratuit — MIT</string>
</dict>
</plist>
PLIST

# Signature. With a stable identity, macOS keeps the permissions (Full Disk Access, Accessibility, folders…)
# from one rebuild to the next. In order: CMC_SIGN_IDENTITY if set, else the local certificate made by
# scripts/setup_signing.sh ("Clean My Claude Dev"), else ad hoc (macOS then forgets the permissions at every rebuild).
IDENTITY="${CMC_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  # The SHA-1 of the local certificate (it is self-signed, hence "not trusted": codesign accepts it by its hash).
  IDENTITY="$(security find-identity -p codesigning 2>/dev/null | awk '/"Clean My Claude Dev"/ {print $2; exit}')"
fi
if [[ -n "$IDENTITY" ]]; then
  echo "→ Signature stable (les autorisations de macOS sont conservées)…"
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "  Astuce : lance une fois ./scripts/setup_signing.sh pour ne plus redonner les autorisations après chaque compilation."
fi

if [[ $ZIP -eq 1 ]]; then
  (cd "$BUILD_DIR" && rm -f CleanMyClaude.zip && ditto -c -k --keepParent "$DISPLAY_NAME.app" CleanMyClaude.zip)
  echo "✓ Archive : $BUILD_DIR/CleanMyClaude.zip"
fi

if [[ $INSTALL -eq 1 ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  rm -rf "$DEST/$DISPLAY_NAME.app"
  cp -R "$APP" "$DEST/"
  # Register the app and its Finder service right away.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/$DISPLAY_NAME.app" >/dev/null 2>&1 || true
  /System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
  echo "✓ Installée dans $DEST/$DISPLAY_NAME.app"
else
  echo "✓ App prête : $APP"
fi
