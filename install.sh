#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
APP_SOURCE="$ROOT_DIR/build/Beijing Clock.app"
APP_DEST="$HOME/Applications/Beijing Clock.app"
AGENT="$HOME/Library/LaunchAgents/com.chen.dualtime.plist"
UID_VALUE=$(id -u)

"$ROOT_DIR/build.sh"
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
ditto "$APP_SOURCE" "$APP_DEST"

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.chen.dualtime</string>
  <key>ProgramArguments</key>
  <array><string>$APP_DEST/Contents/MacOS/BeijingClock</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID_VALUE/com.chen.dualtime" 2>/dev/null || true
launchctl bootstrap "gui/$UID_VALUE" "$AGENT"
echo "Installed: $APP_DEST"
