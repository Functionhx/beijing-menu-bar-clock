# Shared helpers for build.sh / install.sh / scripts/release.sh (zsh, sourced).

ROOT_DIR=${ROOT_DIR:-${0:A:h}}
CONFIG="$ROOT_DIR/Config/Branch.xcconfig"

config_value() {
  sed -n "s/^$1 *= *//p" "$CONFIG" | head -1
}

APP_NAME=$(config_value BMC_PRODUCT_NAME)
BRANCH_NAME=$(config_value BMC_BRANCH)
BUNDLE_ID=$(config_value BMC_BUNDLE_ID)
VERSION=$(config_value MARKETING_VERSION)
BUILD_NUMBER=$(config_value CURRENT_PROJECT_VERSION)

generate_project() {
  "$ROOT_DIR/scripts/fetch-sparkle.sh"
  (cd "$ROOT_DIR" && xcodegen generate --quiet)
}
