#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
source "$ROOT_DIR/scripts/common.sh"
APP_SOURCE="$ROOT_DIR/build/$APP_NAME.app"
APP_DEST="$HOME/Applications/$APP_NAME.app"
# Older installs started the app with a per-user LaunchAgent; the ultra edition uses
# SMAppService (System Settings › General › Login Items) instead.
LEGACY_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
UID_VALUE=$(id -u)

"$ROOT_DIR/build.sh"

if [[ -f "$LEGACY_AGENT" ]]; then
  launchctl bootout "gui/$UID_VALUE/$BUNDLE_ID" 2>/dev/null || true
  rm -f "$LEGACY_AGENT"
fi

# Quit a running copy so the new build replaces it cleanly.
pkill -f "$APP_DEST/Contents/MacOS/" 2>/dev/null || true

mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"

# On its first launch from ~/Applications the app registers itself as a login item.
open "$APP_DEST"
echo "Installed: $APP_DEST"
echo "开机启动由应用自己通过「系统设置 › 通用 › 登录项」管理，可在面板的「开机启动」开关里关闭。"
