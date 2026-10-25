#!/bin/bash
TARGET_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.form.autoresign.plist"

launchctl unload "$TARGET_DIR/$PLIST_NAME" 2>/dev/null || true
rm -f "$TARGET_DIR/$PLIST_NAME"

echo "🛑 Фоновый демон FORM // AUTO-RESIGN деактивирован."
