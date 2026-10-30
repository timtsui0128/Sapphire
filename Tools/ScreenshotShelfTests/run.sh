#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-screenshot-checks-build.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
source = (root/'Sapphire/LiveActivities/LiveActivityManager.swift').read_text()
start = source.index('private func checkForFileShelf()')
end = source.index('{', start) + 1
depth = 1
while depth:
    if source[end] == '{': depth += 1
    elif source[end] == '}': depth -= 1
    end += 1
method = source[start:end]
wrapper = '''
    func candidateCount() -> Int? {
        guard let candidate = checkForFileShelf() else { return nil }
        if case .standard(.fileShelf(let count), _) = candidate.1 { return count }
        return nil
    }
'''
(scratch/'FileShelfCandidate.swift').write_text('import Foundation\nextension FileShelfActivityFixture {\n'+method+wrapper+'\n}')
controller = (root/'Sapphire/Notch/NotchController.swift').read_text()
start = controller.index('    private func openPendingScreenshots(')
end = controller.index('\n    private func receivePointerHover(', start)
method = controller[start:end]
wrapper = '''
    func clickScreenshotPriority(_ manager: ScreenshotShelfManager) -> Bool {
        openPendingScreenshots(config: ResolvedNotchConfiguration(), screenshotManager: manager)
    }
'''
(scratch/'ScreenshotClickRouting.swift').write_text('import AppKit\nimport SwiftUI\nextension ScreenshotClickFixture {\n'+method+wrapper+'\n}')
tap = controller[controller.index('    private func handleTap()'):start]
assert tap.index('flags.contains(.command)') < tap.index('if openPendingScreenshots(')
assert tap.index('if openPendingScreenshots(') < tap.index('if notchState == .clickExpanded')
assert tap.index('if openPendingScreenshots(') < tap.index('if activityType == .music')
PY

xcrun swiftc \
  -swift-version 5 \
  -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT"/Sapphire/Services/Screenshots/*.swift \
  "$REPO_ROOT"/Sapphire/Widgets/Screenshots/*.swift \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/AirDropPayload.swift" \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/QuickAirDrop.swift" \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/TopDropClipboard.swift" \
  "$REPO_ROOT/Sapphire/Services/SessionPrivacy/SessionPrivacyState.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/AlertFixture.swift" \
  "$CHECK_ROOT/ScreenshotClickRouting.swift" \
  "$REPO_ROOT/Tools/ScreenshotShelfTests/ScreenshotClickFixture.swift" \
  "$REPO_ROOT/Tools/ScreenshotShelfTests/FileShelfActivityFixture.swift" \
  "$CHECK_ROOT/FileShelfCandidate.swift" \
  "$REPO_ROOT/Tools/ScreenshotShelfTests/ScreenshotShelfChecks.swift" \
  -o "$CHECK_ROOT/screenshot-shelf-checks"

"$CHECK_ROOT/screenshot-shelf-checks"
