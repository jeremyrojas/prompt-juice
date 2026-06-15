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

if [[ -n "$(git status --porcelain)" ]]; then
  echo "PromptJuice has local changes. Handle them before updating:" >&2
  git status --short >&2
  exit 2
fi

git fetch origin

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "PromptJuice is on a detached HEAD. Check out a branch before updating." >&2
  exit 3
fi

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)"
if [[ -n "$UPSTREAM" ]]; then
  git pull --ff-only
else
  git pull --ff-only origin "$CURRENT_BRANCH"
fi

APP_PATH="$(./scripts/build_app.sh)"

if [[ -d "/Applications/$APP_NAME.app" ]]; then
  DEST_PATH="/Applications/$APP_NAME.app"
elif [[ -d "$HOME/Applications/$APP_NAME.app" ]]; then
  DEST_PATH="$HOME/Applications/$APP_NAME.app"
elif [[ -w "/Applications" ]]; then
  DEST_PATH="/Applications/$APP_NAME.app"
else
  mkdir -p "$HOME/Applications"
  DEST_PATH="$HOME/Applications/$APP_NAME.app"
fi

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

if ! open "$DEST_PATH"; then
  "$DEST_PATH/Contents/MacOS/$APP_NAME" &
fi

echo "Updated PromptJuice to commit: $(git rev-parse --short HEAD)"
echo "Installed PromptJuice to: $DEST_PATH"
echo "If macOS blocks the preview build, right-click PromptJuice.app, choose Open, and approve the prompt."
