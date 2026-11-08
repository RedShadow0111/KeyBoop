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

codesign --force --sign - "$APP"
echo "Built $APP"
