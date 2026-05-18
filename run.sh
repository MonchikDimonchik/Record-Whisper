#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PYTHON_BIN="${PYTHON_BIN:-python3.12}"
PORT="${PORT:-7860}"
URL="http://127.0.0.1:$PORT"

open_app_url() {
  if [ "$(uname)" = "Darwin" ] && open -Ra "Google Chrome" >/dev/null 2>&1; then
    open -a "Google Chrome" "$URL" >/dev/null 2>&1 || true
  else
    open "$URL" >/dev/null 2>&1 || true
  fi
}

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python 3.12 is required. Install it or run with PYTHON_BIN=/path/to/python."
  exit 1
fi

if command -v curl >/dev/null 2>&1 && curl -fsS "$URL/config" >/dev/null 2>&1; then
  echo "Whisper is already running: $URL"
  open_app_url
  exit 0
fi

if [ ! -d ".venv" ]; then
  "$PYTHON_BIN" -m venv .venv
fi

. .venv/bin/activate

STAMP_FILE=".venv/.requirements.stamp"
if [ ! -f "$STAMP_FILE" ] || ! cmp -s requirements.txt "$STAMP_FILE"; then
  python -m pip install -r requirements.txt
  cp requirements.txt "$STAMP_FILE"
fi

python app.py
