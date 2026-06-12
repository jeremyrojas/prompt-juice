#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PromptJuice"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
BINARY_PATH="$ROOT_DIR/.build/$CONFIGURATION/$APP_NAME"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION" >&2

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/app/PromptJuice/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/scripts/claude-statusline-bridge.sh" "$APP_DIR/Contents/Resources/claude-statusline-bridge.sh"
chmod +x "$APP_DIR/Contents/Resources/claude-statusline-bridge.sh"
swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$APP_DIR/Contents/Resources/PromptJuice.icns" >&2

codesign --force --sign - "$APP_DIR" >&2

echo "$APP_DIR"
