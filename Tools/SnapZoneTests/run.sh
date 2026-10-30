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
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Models/SnapZoneModels.swift" \
  "$REPO_ROOT/Sapphire/Services/Zones/SnapWindowPlacement.swift" \
  "$CHECK_ROOT/WindowDragState.swift" \
  "$REPO_ROOT/Tools/SnapZoneTests/SnapChecks.swift" \
  -o "$CHECK_ROOT/snap-checks"
"$CHECK_ROOT/snap-checks"
