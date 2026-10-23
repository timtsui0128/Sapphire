#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RENDER_OUTPUT="${1:-"$REPO_ROOT/output/sports-renders"}"
RENDER_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-sports-render.XXXXXX")"
trap 'rm -rf "$RENDER_TEMP"' EXIT
mkdir -p "$RENDER_OUTPUT" "$REPO_ROOT/output/swift-module-cache"

# Compile the actual board, rows, and compact widget, omitting only the main
# Settings wrapper whose editing session belongs to the full application.
python3 - "$REPO_ROOT" "$RENDER_TEMP" <<'PY'
from pathlib import Path
import sys
root, temporary = map(Path, sys.argv[1:])
source = (root / "Sapphire/Widgets/CommunitySports/CommunitySportsViews.swift").read_text()
marker = "@MainActor\nstruct CommunitySportsSettingsView"
assert marker in source
(temporary / "CommunitySportsBoard.swift").write_text(source.split(marker, 1)[0])
PY

xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/Services/CommunitySports/CommunitySportsService.swift" \
  "$REPO_ROOT/Sapphire/Services/CommunitySports/F1LiveTimingService.swift" \
  "$REPO_ROOT/Sapphire/Widgets/CommunitySports/F1LiveViews.swift" \
  "$RENDER_TEMP/CommunitySportsBoard.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/EmbeddedWidgetRender.swift" \
  "$REPO_ROOT/Tools/CommunitySportsTests/RenderSports.swift" \
  -o "$RENDER_TEMP/render-sports"
"$RENDER_TEMP/render-sports" "$RENDER_OUTPUT"
