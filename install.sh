#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
source "$ROOT_DIR/scripts/common.sh"
APP_SOURCE="$ROOT_DIR/build/$APP_NAME.app"
APP_DEST="$HOME/Applications/$APP_NAME.app"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
UID_VALUE=$(id -u)

"$ROOT_DIR/build.sh"
# Quit a copy that was opened by hand so launchd's RunAtLoad start below doesn't make a second clock.
pkill -f "$APP_DEST/Contents/MacOS/" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key>
  <array><string>$APP_DEST/Contents/MacOS/BeijingClock</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>AssociatedBundleIdentifiers</key>
  <array><string>$BUNDLE_ID</string></array>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID_VALUE/$BUNDLE_ID" 2>/dev/null || true
for attempt in 1 2 3; do
  if launchctl bootstrap "gui/$UID_VALUE" "$AGENT"; then
    break
  fi
  if [[ $attempt == 3 ]]; then
    exit 1
  fi
  sleep 1
done
echo "Installed: $APP_DEST"
