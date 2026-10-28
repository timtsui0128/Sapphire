#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-quick-airdrop.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
APP_ROOT="$CHECK_ROOT/QuickAirDropChecks.app/Contents"
mkdir -p "$REPO_ROOT/output/swift-module-cache" "$APP_ROOT/MacOS" "$APP_ROOT/Resources"
cat > "$APP_ROOT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>checks</string>
<key>CFBundleIdentifier</key><string>local.sapphire.quick-airdrop-checks</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun xcstringstool compile --output-directory "$APP_ROOT/Resources" "$REPO_ROOT/Sapphire/Resources/Localizable.xcstrings"
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/QuickAirDrop/*.swift \
  "$REPO_ROOT/Tools/QuickAirDropTests/Fixtures.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/AlertFixture.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/QuickAirDropChecks.swift" \
  -o "$APP_ROOT/MacOS/checks"
"$APP_ROOT/MacOS/checks" "$REPO_ROOT/output/internal-airdrop/renders"
