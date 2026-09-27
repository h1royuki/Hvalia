#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run HvaliaChecks

./scripts/check-native.sh

./scripts/check-ui.sh
