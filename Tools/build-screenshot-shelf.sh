#!/bin/bash
set -euo pipefail

# Builds the actual screenshot feature in a small native host. No package downloads,
# project format conversion, signing account, or Sapphire private sources required.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="${1:-"$REPO_ROOT/output"}"
APP_PATH="$OUTPUT_ROOT/Sapphire Screenshots.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$OUTPUT_ROOT/swift-module-cache"

xcrun swiftc \
  -swift-version 5 \
  -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$OUTPUT_ROOT/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT"/Sapphire/Services/Screenshots/*.swift \
  "$REPO_ROOT"/Sapphire/Widgets/Screenshots/*.swift \
  "$REPO_ROOT/Tools/ScreenshotShelfPreview/ScreenshotShelfPreviewApp.swift" \
  -o "$APP_PATH/Contents/MacOS/SapphireScreenshots"

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sapphire Screenshots</string>
    <key>CFBundleDisplayName</key><string>Sapphire Screenshots</string>
    <key>CFBundleIdentifier</key><string>com.sapphire.ScreenshotShelfPreview</string>
    <key>CFBundleExecutable</key><string>SapphireScreenshots</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDesktopFolderUsageDescription</key><string>Collect newly saved screenshots and keep them ready for multi-file dragging.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Collect screenshots when Documents is your screenshot save location.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Collect screenshots when Downloads is your screenshot save location.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_PATH"
printf '%s\n' "$APP_PATH"
