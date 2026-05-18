#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHORTCUT="$HOME/Desktop/Whisper.command"

chmod +x "$PROJECT_DIR/run.sh" "$PROJECT_DIR/Whisper.command"
ln -sf "$PROJECT_DIR/Whisper.command" "$SHORTCUT"

echo "Shortcut installed: $SHORTCUT"
