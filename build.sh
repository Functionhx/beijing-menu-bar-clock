#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
source "$ROOT_DIR/scripts/common.sh"
BUILD_DIR="$ROOT_DIR/build"
APP="$BUILD_DIR/$APP_NAME.app"

generate_project
mkdir -p "$BUILD_DIR"
LOG="$BUILD_DIR/xcodebuild.log"
# Keep the exit status: a failed build must not fall through and ship the previous product.
if xcodebuild -project "$ROOT_DIR/BeijingClock.xcodeproj" -scheme BeijingClock -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" build -quiet >"$LOG" 2>&1; then
  build_failed=0
else
  build_failed=1
fi
# Show compiler diagnostics only (xcodebuild also logs unrelated plug-in and simulator noise).
grep -E "^/.*: (error|warning): |^error: " "$LOG" || true
if (( build_failed )); then
  echo "Build failed; full log: $LOG" >&2
  exit 1
fi

rm -rf "$APP"
ditto "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" "$APP"
echo "Built: $APP"
