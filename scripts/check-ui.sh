#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product Hvalia
BIN_DIR="$(swift build --show-bin-path)"
xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library -D HVALIA_UI_CHECKS -module-name Hvalia \
  -I "$BIN_DIR/Modules" Sources/Hvalia/*.swift Tests/HvaliaUITests/*.swift \
  "$BIN_DIR"/HvaliaCore.build/*.swift.o -o "$BIN_DIR/HvaliaUIChecks"
"$BIN_DIR/HvaliaUIChecks" --demo "$@"
