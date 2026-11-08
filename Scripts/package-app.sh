#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

ARCH_DIR=".build/arm64-apple-macosx/release"
APP="dist/KeyBoop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ARCH_DIR/KeyBoop" "$APP/Contents/MacOS/KeyBoop"
cp "Scripts/Info.plist" "$APP/Contents/Info.plist"

DICT=$(find "$ARCH_DIR" -type d -name Dictionaries -print -quit)
cp -R "$DICT" "$APP/Contents/Resources/Dictionaries"

ICONSET="$APP/Contents/Resources/AppIcon.iconset"
rm -rf "$ICONSET"
"$ARCH_DIR/KeyBoopIcon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

if security find-certificate -c "KeyBoop Local" >/dev/null 2>&1; then
  codesign --force --sign "KeyBoop Local" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
