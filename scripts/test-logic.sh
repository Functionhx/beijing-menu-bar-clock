#!/bin/zsh
# Compiles the ultra edition's pure-logic sources with the plain-assertion test runner and runs it.
set -euo pipefail
ROOT_DIR=${0:A:h:h}
OUT=$(mktemp -d)/ultra-logic-tests
swiftc -O \
  "$ROOT_DIR/Sources/WorldClockModel.swift" \
  "$ROOT_DIR/Sources/LunarCalendar.swift" \
  "$ROOT_DIR/Sources/SolarTerms.swift" \
  "$ROOT_DIR/Sources/WorkSchedule.swift" \
  "$ROOT_DIR/Sources/Alarm.swift" \
  "$ROOT_DIR/Tests/UltraLogic/main.swift" \
  -o "$OUT"
"$OUT"
