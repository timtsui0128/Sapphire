#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WIDGET_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-original-widget-render.XXXXXX")"
trap 'rm -rf "$WIDGET_TEMP"' EXIT
WIDGET_OUTPUT="${1:-"$REPO_ROOT/output/appearance-renders"}"
mkdir -p "$REPO_ROOT/output/swift-module-cache" "$WIDGET_OUTPUT"

# Compile exact production controls. Only their unrelated parent service
# dependencies are omitted; the actual view bodies are not duplicated.
python3 - "$REPO_ROOT" "$WIDGET_TEMP" <<'PY'
from pathlib import Path
import sys
root, temporary = map(Path, sys.argv[1:])
def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    level = 1
    end = opening + 1
    while level:
        if source[end] == "{": level += 1
        elif source[end] == "}": level -= 1
        end += 1
    return source[start:end]
source = "import SwiftUI\n"
audio = (root / "Sapphire/Widgets/Audio/DeviceAdjustView.swift").read_text()
dev = (root / "Sapphire/Widgets/Dev/DevDashboardView.swift").read_text()
source += block(audio, "struct ModernDarkSlider:") + "\n"
source += block(dev, "struct DevMonospaceLog:") + "\n"
source += block(dev, "struct DevIconButton:") + "\n"
(temporary / "ProductionControls.swift").write_text(source)
PY

xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/Widgets/Weather/WeatherWidgetView.swift" \
  "$REPO_ROOT/Sapphire/Widgets/Weather/WeatherDetailView.swift" \
  "$REPO_ROOT/Sapphire/Widgets/Shared/RoundedPillSwitcher.swift" \
  "$WIDGET_TEMP/ProductionControls.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/RenderOriginalWidgets.swift" \
  -o "$WIDGET_TEMP/render-original-widgets"
"$WIDGET_TEMP/render-original-widgets" "$WIDGET_OUTPUT" -SapphireAppAppearanceMode light
"$WIDGET_TEMP/render-original-widgets" "$WIDGET_OUTPUT" -SapphireAppAppearanceMode dark
