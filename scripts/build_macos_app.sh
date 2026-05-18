#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Record-Whisper"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_RESOURCES_DIR="$RESOURCES_DIR/backend"
PYTHON_BIN="${PYTHON_BIN:-python3.12}"
BUILD_VENV="$DIST_DIR/.backend-build-venv"
BUILD_PYTHON="$BUILD_VENV/bin/python"
PYINSTALLER_DIST="$DIST_DIR/pyinstaller-dist"
PYINSTALLER_BUILD="$DIST_DIR/pyinstaller-build"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$BACKEND_RESOURCES_DIR"

if [ ! -x "$BUILD_PYTHON" ]; then
  rm -rf "$BUILD_VENV"
  "$PYTHON_BIN" -m venv "$BUILD_VENV"
  "$BUILD_PYTHON" -m pip install --upgrade pip >/dev/null
  "$BUILD_PYTHON" -m pip install -r "$ROOT_DIR/requirements.txt" pyinstaller >/dev/null
elif ! "$BUILD_PYTHON" -c "import fastapi, faster_whisper, sounddevice, uvicorn, PyInstaller" >/dev/null 2>&1; then
  "$BUILD_PYTHON" -m pip install --upgrade -r "$ROOT_DIR/requirements.txt" pyinstaller >/dev/null
fi

rm -rf "$PYINSTALLER_DIST" "$PYINSTALLER_BUILD"
"$BUILD_PYTHON" -m PyInstaller \
  --noconfirm \
  --clean \
  --name RecordWhisperBackend \
  --distpath "$PYINSTALLER_DIST" \
  --workpath "$PYINSTALLER_BUILD" \
  --specpath "$DIST_DIR" \
  --add-data "$ROOT_DIR/static:static" \
  --add-data "$ROOT_DIR/templates:templates" \
  --collect-all faster_whisper \
  --collect-all ctranslate2 \
  --collect-all tokenizers \
  --hidden-import sounddevice \
  "$ROOT_DIR/app.py" >/dev/null

cp -R "$PYINSTALLER_DIST/RecordWhisperBackend" "$BACKEND_RESOURCES_DIR/"

swiftc \
  -framework Cocoa \
  -framework WebKit \
  "$ROOT_DIR/macos/RecordWhisper/main.swift" \
  -o "$MACOS_DIR/$APP_NAME"

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
  <string>local.record-whisper.desktop</string>
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
  <string>Record-Whisper записывает выбранный микрофон и виртуальные аудиовходы для распознавания речи.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Record-Whisper использует локальное соединение 127.0.0.1 между интерфейсом и внутренним движком распознавания.</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$APP_NAME" "$BACKEND_RESOURCES_DIR/RecordWhisperBackend/RecordWhisperBackend"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR"
  xattr -dr com.apple.provenance "$APP_DIR" 2>/dev/null || true
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || {
    echo "Warning: ad-hoc signing skipped; macOS kept extended attributes on $APP_DIR" >&2
  }
fi

echo "$APP_DIR"
