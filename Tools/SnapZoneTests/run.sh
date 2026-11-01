#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-snap-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
# Compile the production drag state verbatim with inert event monitors. The
# executable never creates AX targets or moves any user application window.
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
source = (root/'Sapphire/Services/System/ActiveAppMonitor.swift').read_text()
start = source.index('@MainActor\nfinal class WindowDragState')
end = source.index('\n@MainActor\nclass ActiveAppMonitor', start)
(scratch/'WindowDragState.swift').write_text('import AppKit\nimport Combine\nimport QuartzCore\n' + source[start:end])
source = (root/'Sapphire/Notch/DragStateManager.swift').read_text()
start = source.index('enum FileDragPasteboard {')
end = source.index('{', start) + 1
depth = 1
while depth:
    if source[end] == '{': depth += 1
    elif source[end] == '}': depth -= 1
    end += 1
(scratch/'FileDragPasteboard.swift').write_text('import AppKit\n' + source[start:end])
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Models/SnapZoneModels.swift" \
  "$REPO_ROOT/Sapphire/Services/Zones/SnapWindowPlacement.swift" \
  "$REPO_ROOT/Sapphire/Services/Zones/SnapActivationRegion.swift" \
  "$REPO_ROOT/Sapphire/Services/Zones/SnapResizeCompatibility.swift" \
  "$REPO_ROOT/Sapphire/Notch/GlobalDragManager.swift" \
  "$CHECK_ROOT/WindowDragState.swift" \
  "$REPO_ROOT/Tools/SnapZoneTests/SnapChecks.swift" \
  -o "$CHECK_ROOT/snap-checks"
"$CHECK_ROOT/snap-checks"
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Notch/NotchHoverMonitor.swift" \
  "$REPO_ROOT/Sapphire/Notch/GlobalDragManager.swift" \
  "$REPO_ROOT/Sapphire/Services/Zones/SnapActivationRegion.swift" \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/AirDropDragPreferences.swift" \
  "$CHECK_ROOT/FileDragPasteboard.swift" \
  "$REPO_ROOT/Tools/SnapZoneTests/HandoffWindowChecks.swift" \
  -o "$CHECK_ROOT/handoff-window-checks"
"$CHECK_ROOT/handoff-window-checks"
