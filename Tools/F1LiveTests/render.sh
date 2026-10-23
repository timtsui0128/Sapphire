#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RENDER_OUTPUT="${1:-"$REPO_ROOT/output/f1-renders"}"
RENDER_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-f1-render.XXXXXX")"
trap 'rm -rf "$RENDER_TEMP"' EXIT
mkdir -p "$RENDER_OUTPUT" "$REPO_ROOT/output/swift-module-cache"
python3 - "$REPO_ROOT" "$RENDER_TEMP" <<'PY'
from pathlib import Path
import sys
root, temporary = map(Path, sys.argv[1:])
source = (root / "Sapphire/Widgets/CommunitySports/F1LiveViews.swift").read_text()
marker = "@MainActor\nstruct F1FollowSettingsView"
assert marker in source
(temporary / "F1LiveTimingPanel.swift").write_text(source.split(marker, 1)[0])
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/Services/CommunitySports/CommunitySportsService.swift" \
  "$REPO_ROOT/Sapphire/Services/CommunitySports/F1LiveTimingService.swift" \
  "$RENDER_TEMP/F1LiveTimingPanel.swift" \
  "$REPO_ROOT/Tools/F1LiveTests/Render.swift" \
  -o "$RENDER_TEMP/render-f1"
"$RENDER_TEMP/render-f1" "$RENDER_OUTPUT"
