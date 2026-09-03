#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_ARGS=(-c release)
if [[ "${NOTCHWORK_UNIVERSAL:-0}" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
DIST="$ROOT/dist"
APP="$DIST/Notch Work.app"
DMG="$DIST/Notch-Work.dmg"

rm -rf "$APP" "$DMG" "$DIST/dmg-root"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST/dmg-root"
cp "$BIN_DIR/NotchWork" "$APP/Contents/MacOS/NotchWork"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/NotchWork"

# Ad-hoc signing is enough for personal local use. Replace '-' with a Developer
# ID Application identity before distributing the app to other people.
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi
cp -R "$APP" "$DIST/dmg-root/"
cp "$ROOT/scripts/install-local.command" "$DIST/dmg-root/Установить Notch Work.command"
chmod +x "$DIST/dmg-root/Установить Notch Work.command"
ln -s /Applications "$DIST/dmg-root/Applications"
hdiutil create -volname "Notch Work" -srcfolder "$DIST/dmg-root" -ov -format UDZO "$DMG"
rm -rf "$DIST/dmg-root"

echo "Created: $APP"
echo "Created: $DMG"
