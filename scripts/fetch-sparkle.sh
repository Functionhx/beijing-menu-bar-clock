#!/bin/zsh
# Downloads the pinned Sparkle release into Vendor/Sparkle (framework + bin/ signing tools).
# Xcode's own SwiftPM binary-artifact download hangs on some networks, so we fetch with curl
# and verify the published checksum instead.
set -euo pipefail

ROOT_DIR=${0:A:h:h}
SPARKLE_VERSION=2.10.0
SPARKLE_SHA256=17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959
DEST="$ROOT_DIR/Vendor/Sparkle"

if [[ -f "$DEST/.version" && $(<"$DEST/.version") == "$SPARKLE_VERSION" ]]; then
  exit 0
fi

ZIP=$(mktemp -t sparkle).zip
trap 'rm -f "$ZIP"' EXIT
curl -fsSL --retry 3 -o "$ZIP" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-for-Swift-Package-Manager.zip"
echo "$SPARKLE_SHA256  $ZIP" | shasum -a 256 -c - >/dev/null

rm -rf "$DEST"
mkdir -p "$DEST"
ditto -x -k "$ZIP" "$DEST"
echo "$SPARKLE_VERSION" > "$DEST/.version"
echo "Sparkle $SPARKLE_VERSION → $DEST"
