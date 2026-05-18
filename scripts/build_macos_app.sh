#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Whisper Local"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_RESOURCES_DIR="$RESOURCES_DIR/app"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$APP_RESOURCES_DIR"

swiftc \
  -framework Cocoa \
  -framework WebKit \
  "$ROOT_DIR/macos/WhisperLocal/main.swift" \
  -o "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/app.py" "$APP_RESOURCES_DIR/"
cp "$ROOT_DIR/requirements.txt" "$APP_RESOURCES_DIR/"
cp "$ROOT_DIR/desktop_run.sh" "$APP_RESOURCES_DIR/"
cp -R "$ROOT_DIR/static" "$APP_RESOURCES_DIR/"
cp -R "$ROOT_DIR/templates" "$APP_RESOURCES_DIR/"

ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
swift "$ROOT_DIR/scripts/generate_macos_assets.swift" iconset "$ICONSET_DIR"
sips -z 16 16 "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

if [ "${INCLUDE_MODELS:-0}" = "1" ] && [ -d "$ROOT_DIR/models" ]; then
  cp -R "$ROOT_DIR/models" "$APP_RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ru</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>local.whisper.desktop</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Whisper Local записывает выбранный микрофон и виртуальные аудиовходы для распознавания речи.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Whisper Local использует локальное соединение 127.0.0.1 между интерфейсом и внутренним движком распознавания.</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$APP_NAME" "$APP_RESOURCES_DIR/desktop_run.sh"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
