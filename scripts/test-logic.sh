#!/bin/zsh
# Compiles and runs the pure-logic tests (no app, no UI).
set -euo pipefail
ROOT_DIR=${0:A:h:h}
OUT=/tmp/bmc-logic-tests
swiftc "$ROOT_DIR"/Sources/{ImportantDate,LunarCalendar}.swift "$ROOT_DIR/Tests/ImportantDates/main.swift" -o $OUT
$OUT
