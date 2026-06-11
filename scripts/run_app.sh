#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/scripts/build_app.sh")"

if pgrep -x PromptJuice >/dev/null; then
  pkill -x PromptJuice

  for _ in {1..30}; do
    if ! pgrep -x PromptJuice >/dev/null; then
      break
    fi

    sleep 0.1
  done

  sleep 1
fi

if ! open "$APP_PATH"; then
  "$APP_PATH/Contents/MacOS/PromptJuice" &
fi
