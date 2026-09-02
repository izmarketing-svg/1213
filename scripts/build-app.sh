#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
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
codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP"
cp -R "$APP" "$DIST/dmg-root/"
ln -s /Applications "$DIST/dmg-root/Applications"
hdiutil create -volname "Notch Work" -srcfolder "$DIST/dmg-root" -ov -format UDZO "$DMG"
rm -rf "$DIST/dmg-root"

echo "Created: $APP"
echo "Created: $DMG"
