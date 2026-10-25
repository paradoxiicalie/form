#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.form.autoresign.plist"

mkdir -p "$TARGET_DIR"
cp "$SCRIPT_DIR/$PLIST_NAME" "$TARGET_DIR/$PLIST_NAME"

launchctl unload "$TARGET_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$TARGET_DIR/$PLIST_NAME"

echo "✅ Фоновый демон FORM // AUTO-RESIGN успешно активирован в macOS!"
echo "Он будет каждые 2 часа проверять подключение твоего iPhone по Wi-Fi («планета») или USB."
echo "Раз в 4 дня при сопряжении он сам тихо переподпишет и обновит приложение form."
echo "Проверить статус в любой момент: ./scripts/autoresign.sh --status"
