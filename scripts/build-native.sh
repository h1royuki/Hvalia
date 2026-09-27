#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build-native
export MACOSX_DEPLOYMENT_TARGET=14.0
xcrun clang -fobjc-arc -O2 -Wall -Wextra -framework Foundation -framework CoreFoundation /System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice Native/device_helper.m -o .build-native/hvalia-device
xcrun clang -fobjc-arc -O2 -Wall -Wextra -framework Foundation /System/Library/PrivateFrameworks/AirTrafficHost.framework/AirTrafficHost Native/airtraffic_host.m -o .build-native/hvalia-atc
codesign --force --sign - .build-native/hvalia-device
codesign --force --sign - .build-native/hvalia-atc
