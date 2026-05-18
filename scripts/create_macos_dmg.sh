#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/Whisper Local.dmg"
VOLUME_NAME="Whisper Local"
DMGBUILD_VENV="$DIST_DIR/.dmgbuild-venv"
DMGBUILD_PYTHON="$DMGBUILD_VENV/bin/python"
BACKGROUND_PATH="$DIST_DIR/dmg-background.png"
PYTHON_BIN="${PYTHON_BIN:-python3.12}"

"$ROOT_DIR/scripts/build_macos_app.sh" >/dev/null

mkdir -p "$DIST_DIR"
swift "$ROOT_DIR/scripts/generate_macos_assets.swift" background "$BACKGROUND_PATH"
sips -z 440 760 "$BACKGROUND_PATH" >/dev/null

if [ ! -x "$DMGBUILD_PYTHON" ]; then
  rm -rf "$DMGBUILD_VENV"
  "$PYTHON_BIN" -m venv "$DMGBUILD_VENV"
  "$DMGBUILD_PYTHON" -m pip install --upgrade pip dmgbuild >/dev/null
elif ! "$DMGBUILD_PYTHON" -c "import dmgbuild" >/dev/null 2>&1; then
  "$DMGBUILD_PYTHON" -m pip install --upgrade dmgbuild >/dev/null
fi

rm -f "$DMG_PATH"
"$DMGBUILD_PYTHON" -m dmgbuild \
  -s "$ROOT_DIR/scripts/dmgbuild_settings.py" \
  -D "root=$ROOT_DIR" \
  "$VOLUME_NAME" \
  "$DMG_PATH"

echo "$DMG_PATH"
