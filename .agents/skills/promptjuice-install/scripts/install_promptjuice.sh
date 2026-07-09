#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
APP_NAME="PromptJuice"

cd "$ROOT_DIR"

if [[ ! -x "scripts/build_app.sh" ]]; then
  echo "Expected PromptJuice repository root at: $ROOT_DIR" >&2
  exit 1
fi

APP_PATH="$(./scripts/build_app.sh)"

if [[ -w "/Applications" ]]; then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi

DEST_PATH="$INSTALL_DIR/$APP_NAME.app"

if pgrep -x "$APP_NAME" >/dev/null; then
  pkill -x "$APP_NAME"
  for _ in {1..50}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      break
    fi
    sleep 0.1
  done
fi

rm -rf "$DEST_PATH"
ditto "$APP_PATH" "$DEST_PATH"
touch "$DEST_PATH"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_PATH" >/dev/null 2>&1 || true
fi
/usr/bin/mdimport "$DEST_PATH" >/dev/null 2>&1 || true

if ! open "$DEST_PATH"; then
  "$DEST_PATH/Contents/MacOS/$APP_NAME" &
fi

echo "Installed PromptJuice to: $DEST_PATH"
echo "If macOS blocks the preview build, right-click PromptJuice.app, choose Open, and approve the prompt."
