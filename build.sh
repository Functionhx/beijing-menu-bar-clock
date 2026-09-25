#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
source "$ROOT_DIR/scripts/common.sh"
BUILD_DIR="$ROOT_DIR/build"
APP="$BUILD_DIR/$APP_NAME.app"

generate_project
xcodebuild -project "$ROOT_DIR/BeijingClock.xcodeproj" -scheme BeijingClock -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" build -quiet 2>&1 | grep -E "error|warning: .*\.swift" || true

rm -rf "$APP"
ditto "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" "$APP"
echo "Built: $APP"
