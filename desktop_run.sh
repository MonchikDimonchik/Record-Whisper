#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PYTHON_BIN="${PYTHON_BIN:-python3.12}"
PORT="${PORT:-7860}"
APP_SUPPORT="${HOME}/Library/Application Support/Record-Whisper"
VENV_DIR="${APP_SUPPORT}/.venv"
STAMP_FILE="${VENV_DIR}/.requirements.stamp"

mkdir -p "$APP_SUPPORT"

export PORT
export WHISPER_OPEN_BROWSER=0
export WHISPER_DATA_DIR="$APP_SUPPORT"

if [ -d "$PWD/models" ]; then
  export WHISPER_MODEL_DIR="$PWD/models"
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  osascript -e 'display dialog "Record-Whisper requires Python 3.12. Install Python 3.12 and launch the app again." buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1 || true
  exit 1
fi

if [ ! -d "$VENV_DIR" ]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

. "$VENV_DIR/bin/activate"

if [ ! -f "$STAMP_FILE" ] || ! cmp -s requirements.txt "$STAMP_FILE"; then
  python -m pip install -r requirements.txt
  cp requirements.txt "$STAMP_FILE"
fi

python app.py
