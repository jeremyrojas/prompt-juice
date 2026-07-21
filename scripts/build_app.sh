#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PromptJuice"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
BINARY_PATH="$ROOT_DIR/.build/$CONFIGURATION/$APP_NAME"
MASCOT_ICON_SOURCE="$ROOT_DIR/design/assets/promptjuice-mascot-happy.png"

cd "$ROOT_DIR"

sign_app_bundle() {
    local bundle_identifier="$1"
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"; trap - RETURN' RETURN

    cat > "$tmpdir/requirements.txt" <<EOF
designated => identifier "$bundle_identifier"
EOF

    echo "Signing $APP_NAME.app with stable local requirement: $bundle_identifier" >&2
    codesign --force --sign - --requirements "$tmpdir/requirements.txt" "$APP_DIR" >&2
    trap - RETURN
    rm -rf "$tmpdir"
}

swift build -c "$CONFIGURATION" >&2

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/app/PromptJuice/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$MASCOT_ICON_SOURCE" "$APP_DIR/Contents/Resources/PromptJuiceMascot.png"
swift "$ROOT_DIR/scripts/generate_app_icon.swift" \
    "$MASCOT_ICON_SOURCE" \
    "$APP_DIR/Contents/Resources/PromptJuice.icns" >&2

BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
sign_app_bundle "$BUNDLE_IDENTIFIER"

echo "$APP_DIR"
