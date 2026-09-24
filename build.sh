#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
BUILD_DIR="$ROOT_DIR/build"
APP="$BUILD_DIR/Beijing Clock.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc "$ROOT_DIR"/Sources/*.swift \
  -o "$APP/Contents/MacOS/BeijingClock" \
  -framework AppKit \
  -framework AVFoundation \
  -framework SwiftUI \
  -parse-as-library \
  -O

cp "$ROOT_DIR/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
