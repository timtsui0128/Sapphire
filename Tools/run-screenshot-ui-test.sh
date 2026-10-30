#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="$REPO_ROOT/output"
APP_PATH="$OUTPUT_ROOT/Screenshot Shelf UI Test.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$OUTPUT_ROOT/swift-module-cache"
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$OUTPUT_ROOT/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT"/Sapphire/Services/Screenshots/*.swift \
  "$REPO_ROOT"/Sapphire/Widgets/Screenshots/*.swift \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/AirDropPayload.swift" \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/QuickAirDrop.swift" \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/TopDropClipboard.swift" \
  "$REPO_ROOT/Sapphire/Services/SessionPrivacy/SessionPrivacyState.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/AlertFixture.swift" \
  "$REPO_ROOT/Tools/ScreenshotShelfTests/UIHarness.swift" \
  -o "$APP_PATH/Contents/MacOS/ScreenshotShelfUITest"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Screenshot Shelf UI Test</string>
<key>CFBundleIdentifier</key><string>com.sapphire.ScreenshotShelfUITest</string>
<key>CFBundleExecutable</key><string>ScreenshotShelfUITest</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP_PATH"
printf '%s\n' "$APP_PATH"
