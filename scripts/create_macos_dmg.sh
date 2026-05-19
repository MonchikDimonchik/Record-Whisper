#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/Record-Whisper.dmg"
VOLUME_NAME="Record-Whisper"
STAGING_DIR=""

cleanup() {
  if [ -n "$STAGING_DIR" ]; then
    rm -rf "$STAGING_DIR"
  fi
}

trap cleanup EXIT

"$ROOT_DIR/scripts/build_macos_app.sh" >/dev/null
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$DIST_DIR/Record-Whisper.app" 2>/dev/null || true
  find "$DIST_DIR/Record-Whisper.app" -exec xattr -c {} + 2>/dev/null || true
fi

mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d /tmp/record-whisper-dmg.XXXXXX)"
mkdir -p "$STAGING_DIR"
ditto --norsrc --noextattr "$DIST_DIR/Record-Whisper.app" "$STAGING_DIR/Record-Whisper.app"
ln -s /Applications "$STAGING_DIR/Applications"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$STAGING_DIR/Record-Whisper.app" >/dev/null
  codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/Record-Whisper.app" >/dev/null
fi

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
