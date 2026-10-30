#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-quick-airdrop.XXXXXX")"
trap '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$CHECK_ROOT/QuickAirDropChecks.app" >/dev/null 2>&1 || true; rm -rf "$CHECK_ROOT"' EXIT
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
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        end += 1
    return source[start:end]
probe = block((root/'Sapphire/Notch/NotchHoverMonitor.swift').read_text(), 'final class HoverProbeWindow:')
pasteboard = block((root/'Sapphire/Notch/DragStateManager.swift').read_text(), 'enum FileDragPasteboard {')
(scratch/'ProductionTopDrop.swift').write_text('import AppKit\n'+probe+'\n'+pasteboard+'\n')
card = block((root/'Sapphire/Widgets/Dropbox/FileDragLandingView.swift').read_text(), 'private struct DropZoneView:').replace('private struct', 'struct', 1)
(scratch/'ProductionDropCard.swift').write_text('import SwiftUI\n'+card+'\n')
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/QuickAirDrop/*.swift \
  "$REPO_ROOT/Tools/QuickAirDropTests/Fixtures.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/AlertFixture.swift" \
  "$CHECK_ROOT/ProductionTopDrop.swift" \
  "$CHECK_ROOT/ProductionDropCard.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/TopDropChecks.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/ClipboardDropChecks.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/QuickAirDropChecks.swift" \
  -o "$APP_ROOT/MacOS/checks"
"$APP_ROOT/MacOS/checks" "$REPO_ROOT/output/internal-airdrop/renders"
