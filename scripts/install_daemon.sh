#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.form.autoresign.plist"

mkdir -p "$TARGET_DIR"
cp "$SCRIPT_DIR/$PLIST_NAME" "$TARGET_DIR/$PLIST_NAME"

launchctl unload "$TARGET_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$TARGET_DIR/$PLIST_NAME"

echo "✅ Фоновый демон FORM // AUTO-RESIGN успешно активирован в macOS!"
echo "Он будет каждый час проверять доступность твоего iPhone по Wi-Fi («планета») или USB."
echo "Каждые 2 дня при обнаружении iPhone он бесшовно переподписывает и обновляет приложение form."
echo "Проверить статус в любой момент: ./scripts/autoresign.sh --status"
