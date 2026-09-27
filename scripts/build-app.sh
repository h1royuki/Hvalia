#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-native.sh
swift build -c release --product Hvalia
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Hvalia.app"
# Only replace this project's generated bundle.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN_DIR/Hvalia" "$APP/Contents/MacOS/Hvalia"
cp .build-native/hvalia-device .build-native/hvalia-atc "$APP/Contents/Helpers/"
cp Native/LICENSE.airlift "$APP/Contents/Resources/"
cp LICENSE README.md docs/RECOVERY.md docs/COMPATIBILITY.md "$APP/Contents/Resources/"
./scripts/build-icon.sh
cp .build-native/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Hvalia</string>
<key>CFBundleDisplayName</key><string>Hvalia</string>
<key>CFBundleIdentifier</key><string>io.github.h1royuki.hvalia</string>
<key>CFBundleExecutable</key><string>Hvalia</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>ru</string><string>be</string><string>en</string></array>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Helpers/hvalia-device"
codesign --force --sign - "$APP/Contents/Helpers/hvalia-atc"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$APP" "dist/Hvalia-1.0.0-$(uname -m).zip"
(cd dist && shasum -a 256 "Hvalia-1.0.0-$(uname -m).zip" > SHA256SUMS.txt)
echo "Built $APP"
