#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/macos"
ASSET_DIR="$BUILD_DIR/assets"
PYI_DIST_DIR="$BUILD_DIR/pyinstaller-dist"
PYI_WORK_DIR="$BUILD_DIR/pyinstaller-work"
PYI_SPEC_DIR="$BUILD_DIR/pyinstaller-spec"
APP_PATH="$BUILD_DIR/DouyinLiveRecorder.app"
OUTPUT_DIR="$ROOT_DIR/dist"
OUTPUT_DMG="$OUTPUT_DIR/DouyinLiveRecorder-macOS-arm64.dmg"
APP_NAME="DouyinLiveRecorder"
CORE_NAME="DouyinLiveRecorderCore"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
UV_BIN="${UV_BIN:-uv}"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dlyr-macos-package.XXXXXX")"
SIGNED_APP_PATH="$TEMP_ROOT/${APP_NAME}.app"
DMG_ROOT="$TEMP_ROOT/dmg-root"

trap 'rm -rf "$TEMP_ROOT"' EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This packaging script currently targets macOS arm64." >&2
  exit 1
fi

command -v "$UV_BIN" >/dev/null 2>&1 || {
  echo "uv is required. Install it from https://docs.astral.sh/uv/ first." >&2
  exit 1
}

mkdir -p "$BUILD_DIR" "$ASSET_DIR" "$OUTPUT_DIR"

echo "==> Creating Python $PYTHON_VERSION build environment"
"$UV_BIN" venv --clear --python "$PYTHON_VERSION" "$BUILD_DIR/.venv"
"$UV_BIN" pip install --python "$BUILD_DIR/.venv/bin/python" -U pip wheel pyinstaller
"$UV_BIN" pip install --python "$BUILD_DIR/.venv/bin/python" -r "$ROOT_DIR/requirements.txt"

echo "==> Downloading Node.js LTS for macOS arm64"
NODE_VERSION="${NODE_VERSION:-$("$ROOT_DIR/build/macos/.venv/bin/python" - <<'PY'
import json
import urllib.request

with urllib.request.urlopen("https://nodejs.org/dist/index.json") as response:
    releases = json.load(response)
for release in releases:
    if release.get("lts") and "osx-arm64-tar" in release.get("files", []):
        print(release["version"])
        break
else:
    raise SystemExit("No Node.js LTS macOS arm64 build found")
PY
)}"
NODE_ARCHIVE="node-${NODE_VERSION}-darwin-arm64.tar.gz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_ARCHIVE}"
if [[ ! -d "$ASSET_DIR/node-${NODE_VERSION}-darwin-arm64" ]]; then
  curl -fL "$NODE_URL" -o "$ASSET_DIR/$NODE_ARCHIVE"
  tar -xzf "$ASSET_DIR/$NODE_ARCHIVE" -C "$ASSET_DIR"
fi

echo "==> Downloading FFmpeg static binaries for macOS arm64"
FFMPEG_RELEASE="${FFMPEG_RELEASE:-$("$ROOT_DIR/build/macos/.venv/bin/python" - <<'PY'
import json
import urllib.request

with urllib.request.urlopen("https://api.github.com/repos/eugeneware/ffmpeg-static/releases/latest") as response:
    print(json.load(response)["tag_name"])
PY
)}"
for binary in ffmpeg ffprobe; do
  target="$ASSET_DIR/$binary-darwin-arm64"
  if [[ ! -x "$target" ]]; then
    curl -fL "https://github.com/eugeneware/ffmpeg-static/releases/download/${FFMPEG_RELEASE}/${binary}-darwin-arm64.gz" \
      -o "$target.gz"
    gunzip -f "$target.gz"
    chmod +x "$target"
  fi
done

echo "==> Building PyInstaller core"
rm -rf "$PYI_DIST_DIR" "$PYI_WORK_DIR" "$PYI_SPEC_DIR"
"$BUILD_DIR/.venv/bin/pyinstaller" \
  --noconfirm \
  --clean \
  --name "$CORE_NAME" \
  --onedir \
  --console \
  --distpath "$PYI_DIST_DIR" \
  --workpath "$PYI_WORK_DIR" \
  --specpath "$PYI_SPEC_DIR" \
  --add-data "$ROOT_DIR/config:config" \
  --add-data "$ROOT_DIR/i18n:i18n" \
  --add-data "$ROOT_DIR/src/javascript:src/javascript" \
  --add-data "$ROOT_DIR/index.html:." \
  "$ROOT_DIR/main.py"

echo "==> Assembling app bundle"
rm -rf "$APP_PATH"
mkdir -p \
  "$APP_PATH/Contents/MacOS" \
  "$APP_PATH/Contents/Resources/recorder" \
  "$APP_PATH/Contents/Resources/runtime/node" \
  "$APP_PATH/Contents/Resources/runtime/ffmpeg"

cp -R "$PYI_DIST_DIR/$CORE_NAME" "$APP_PATH/Contents/Resources/recorder/"
cp -R "$ASSET_DIR/node-${NODE_VERSION}-darwin-arm64/." "$APP_PATH/Contents/Resources/runtime/node/"
cp "$ASSET_DIR/ffmpeg-darwin-arm64" "$APP_PATH/Contents/Resources/runtime/ffmpeg/ffmpeg"
cp "$ASSET_DIR/ffprobe-darwin-arm64" "$APP_PATH/Contents/Resources/runtime/ffmpeg/ffprobe"
chmod +x "$APP_PATH/Contents/Resources/runtime/ffmpeg/ffmpeg" "$APP_PATH/Contents/Resources/runtime/ffmpeg/ffprobe"
cp -R "$ROOT_DIR/config" "$APP_PATH/Contents/Resources/config"

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>DouyinLiveRecorder</string>
  <key>CFBundleExecutable</key>
  <string>DouyinLiveRecorder</string>
  <key>CFBundleIdentifier</key>
  <string>com.yuweix.douyinliverecorder</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>DouyinLiveRecorder</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>4.0.7</string>
  <key>CFBundleVersion</key>
  <string>4.0.7.1</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat > "$APP_PATH/Contents/MacOS/DouyinLiveRecorder" <<'LAUNCHER'
#!/bin/zsh
set -e

APP_CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$APP_CONTENTS/Resources/recorder/DouyinLiveRecorderCore/DouyinLiveRecorderCore"
APP_DATA="$HOME/Library/Application Support/DouyinLiveRecorder"
mkdir -p "$APP_DATA"

COMMAND="export DLYR_APP_DATA_DIR=$(printf '%q' "$APP_DATA"); $(printf '%q' "$CORE")"
ESCAPED_COMMAND="${COMMAND//\\/\\\\}"
ESCAPED_COMMAND="${ESCAPED_COMMAND//\"/\\\"}"

/usr/bin/osascript <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "$ESCAPED_COMMAND"
end tell
APPLESCRIPT
LAUNCHER
chmod +x "$APP_PATH/Contents/MacOS/DouyinLiveRecorder"

echo "==> Ad-hoc signing app bundle"
rm -rf "$SIGNED_APP_PATH"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$APP_PATH" "$SIGNED_APP_PATH"
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$SIGNED_APP_PATH"
  xattr -d com.apple.FinderInfo "$SIGNED_APP_PATH" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$SIGNED_APP_PATH" 2>/dev/null || true
fi
/usr/bin/codesign --force --deep --sign - "$SIGNED_APP_PATH"
if command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.FinderInfo "$SIGNED_APP_PATH" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$SIGNED_APP_PATH" 2>/dev/null || true
fi

echo "==> Creating DMG"
rm -rf "$DMG_ROOT" "$OUTPUT_DMG"
mkdir -p "$DMG_ROOT"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$SIGNED_APP_PATH" "$DMG_ROOT/${APP_NAME}.app"
ln -s /Applications "$DMG_ROOT/Applications"

cat > "$DMG_ROOT/Open Config.command" <<'OPENCONFIG'
#!/bin/zsh
set -e

DMG_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$DMG_DIR/DouyinLiveRecorder.app"
SOURCE_CONFIG="$APP_PATH/Contents/Resources/config"
TARGET_CONFIG="$HOME/Library/Application Support/DouyinLiveRecorder/config"

mkdir -p "$TARGET_CONFIG"
if [[ -d "$SOURCE_CONFIG" ]]; then
  for file in "$SOURCE_CONFIG"/*; do
    target="$TARGET_CONFIG/$(basename "$file")"
    [[ -e "$target" ]] || cp "$file" "$target"
  done
fi

open "$TARGET_CONFIG"
OPENCONFIG
chmod +x "$DMG_ROOT/Open Config.command"

cat > "$DMG_ROOT/Install DouyinLiveRecorder.command" <<'INSTALLER'
#!/bin/zsh
set -e

DMG_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$DMG_DIR/DouyinLiveRecorder.app"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/DouyinLiveRecorder.app"

install_app() {
  local target_dir="$1"
  local target_app="$target_dir/DouyinLiveRecorder.app"
  mkdir -p "$target_dir"
  rm -rf "$target_app"
  COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$SOURCE_APP" "$target_app"
  xattr -cr "$target_app" 2>/dev/null || true
  xattr -d com.apple.quarantine "$target_app" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$target_app" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$target_app" 2>/dev/null || true
  echo "$target_app"
}

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Cannot find DouyinLiveRecorder.app next to this installer."
  exit 1
fi

if ! TARGET_APP="$(install_app "$TARGET_DIR" 2>/dev/null)"; then
  TARGET_DIR="$HOME/Applications"
  TARGET_APP="$(install_app "$TARGET_DIR")"
fi

echo "Installed to: $TARGET_APP"
open "$TARGET_APP"
INSTALLER
chmod +x "$DMG_ROOT/Install DouyinLiveRecorder.command"

cat > "$DMG_ROOT/README-mac.txt" <<'README'
DouyinLiveRecorder macOS arm64

1. Double-click "Install DouyinLiveRecorder.command" first.
2. The installer copies DouyinLiveRecorder.app to Applications, removes download quarantine, and starts it.
3. Config files live in:
   ~/Library/Application Support/DouyinLiveRecorder/config
4. Double-click Open Config.command to open the config folder.
5. Do not run DouyinLiveRecorder.app directly from the DMG. Unsigned apps launched from downloaded DMGs are blocked by Gatekeeper.

This build bundles Python, Node.js, FFmpeg, and FFprobe. Homebrew is not required.
README

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

echo "DMG created at: $OUTPUT_DMG"
