#!/bin/zsh
# Builds and runs the control panel test host (Tests/PanelHarness). Usage: scripts/panel-harness.sh [harness args…]
# Example: scripts/panel-harness.sh --clicks "184,181.5;53,245" --shot /tmp/panel.png
set -euo pipefail
ROOT_DIR=${0:A:h:h}
OUT=/tmp/bmc-panel-harness
sources=(${(f)"$(ls "$ROOT_DIR"/Sources/*.swift | grep -v -e AppDelegate.swift -e Updater.swift)"})
if [[ ! -x $OUT || -n $(find "$ROOT_DIR/Sources" "$ROOT_DIR/Tests/PanelHarness" -newer $OUT -name '*.swift') ]]; then
  swiftc -parse-as-library $sources "$ROOT_DIR/Tests/PanelHarness/PanelHarness.swift" -o $OUT
fi
exec $OUT "$@"
