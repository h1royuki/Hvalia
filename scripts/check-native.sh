#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build-native
xcrun clang -fobjc-arc -O0 -Wno-unused-function -framework Foundation -framework CoreFoundation /System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice Tests/Native/BooksRestoreTests.m -o .build-native/books-restore-checks
.build-native/books-restore-checks
