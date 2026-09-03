#!/bin/bash
set -euo pipefail

APP_NAME="Notch Work.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SCRIPT_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Не найдено приложение: $SOURCE_APP"
  read -r -p "Нажмите Enter, чтобы закрыть окно…"
  exit 1
fi

rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
codesign --verify --deep --strict "$TARGET_APP"
open "$TARGET_APP"

echo "Notch Work установлен и запущен. Это действие требуется только для персональной сборки без Apple notarization."
sleep 3
