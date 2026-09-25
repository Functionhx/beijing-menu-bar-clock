#!/bin/zsh
# Builds a signed, update-ready release of the current branch:
#   archive → sign (Developer ID or ad-hoc) → notarize (optional) → zip → EdDSA sign → appcast.xml
# Nothing is uploaded or pushed; the commands to publish are printed at the end.
#
# Optional environment:
#   SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)" — omit for an ad-hoc build
#   NOTARY_PROFILE  keychain profile created with `xcrun notarytool store-credentials`
#   SPARKLE_ACCOUNT keychain account of the Sparkle EdDSA key (default: beijing-menu-bar-clock)
set -euo pipefail

ROOT_DIR=${0:A:h:h}
source "$ROOT_DIR/scripts/common.sh"

SIGN_IDENTITY=${SIGN_IDENTITY:-}
NOTARY_PROFILE=${NOTARY_PROFILE:-}
SPARKLE_ACCOUNT=${SPARKLE_ACCOUNT:-beijing-menu-bar-clock}
SPARKLE_BIN="$ROOT_DIR/Vendor/Sparkle/bin"
REPO_URL="https://github.com/Functionhx/beijing-menu-bar-clock"

TAG="v$VERSION"
OUT_DIR="$ROOT_DIR/build/release"
ARCHIVE="$OUT_DIR/BeijingClock.xcarchive"
APP="$OUT_DIR/$APP_NAME.app"
ZIP_NAME="BeijingClock-$VERSION.zip"
ZIP="$OUT_DIR/$ZIP_NAME"

step() { print -P "%F{cyan}==>%f $1"; }

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

step "Generating project ($BRANCH_NAME $VERSION build $BUILD_NUMBER)"
generate_project

step "Archiving"
xcodebuild -project "$ROOT_DIR/BeijingClock.xcodeproj" -scheme BeijingClock -configuration Release \
  -derivedDataPath "$ROOT_DIR/build/DerivedData" -archivePath "$ARCHIVE" archive -quiet \
  2>&1 | grep -E "error|warning: .*\.swift" || true
ditto "$ARCHIVE/Products/Applications/$APP_NAME.app" "$APP"

# Sign inside-out as Sparkle documents: XPC services, Autoupdate, Updater.app, framework, then the app.
# Hardened runtime + secure timestamp only make sense (and are required for notarization) with a real identity.
if [[ -n "$SIGN_IDENTITY" ]]; then
  step "Signing with $SIGN_IDENTITY"
  SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
else
  print -P "%F{yellow}warning:%f SIGN_IDENTITY not set — ad-hoc signing. Updates still verify via Sparkle EdDSA,"
  print -P "         but Gatekeeper will warn on first launch and the build cannot be notarized."
  SIGN_FLAGS=(--force --sign -)
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Versions/B/Updater.app"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

if [[ -n "$NOTARY_PROFILE" ]]; then
  [[ -n "$SIGN_IDENTITY" ]] || { echo "NOTARY_PROFILE requires SIGN_IDENTITY" >&2; exit 1; }
  step "Notarizing (this can take a few minutes)"
  NOTARY_ZIP="$OUT_DIR/notarize.zip"
  ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$NOTARY_ZIP"
fi

step "Packaging $ZIP_NAME"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Signing update with Sparkle EdDSA key ($SPARKLE_ACCOUNT)"
SIGNATURE_ATTRIBUTES=$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$ZIP")

step "Updating appcast.xml"
MIN_SYSTEM=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")
python3 - "$ROOT_DIR/appcast.xml" <<PY
import sys, email.utils
path = sys.argv[1]
item = f'''    <item>
      <title>$VERSION</title>
      <pubDate>{email.utils.formatdate(localtime=True)}</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$REPO_URL/releases/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="$REPO_URL/releases/download/$TAG/$ZIP_NAME" $SIGNATURE_ATTRIBUTES type="application/octet-stream"/>
    </item>
'''
text = open(path).read()
marker = "<sparkle:version>$BUILD_NUMBER</sparkle:version>"
if marker in text:
    sys.exit("appcast.xml already has build $BUILD_NUMBER — bump CURRENT_PROJECT_VERSION in Config/Branch.xcconfig")
anchor = "<!-- items -->\n"
open(path, "w").write(text.replace(anchor, anchor + item, 1))
PY

step "Done"
cat <<MSG

  App:     $APP
  Archive: $ZIP

To publish (upload the zip first, then push the appcast so clients never see a missing file):

  gh release create "$TAG" "$ZIP" --target "$BRANCH_NAME" --title "$APP_NAME $VERSION" --notes "…"
  git add appcast.xml Config/Branch.xcconfig && git commit -m "Release $TAG"
  git push origin "$BRANCH_NAME"

MSG
