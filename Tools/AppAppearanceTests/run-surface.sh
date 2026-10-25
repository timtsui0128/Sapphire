#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-surface-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
RENDER_OUTPUT="${1:-"$REPO_ROOT/output/appearance-renders"}"
mkdir -p "$REPO_ROOT/output/swift-module-cache" "$RENDER_OUTPUT"
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, temporary = map(Path, sys.argv[1:])
source = (root / "Sapphire/Notch/NotchSurfaceHostView.swift").read_text()
(temporary / "NotchSurfaceStyle.swift").write_text(source.split("@MainActor\nfinal class NotchSurfaceHostView", 1)[0])
source = (root / "Sapphire/Notch/NotchLayerSurface.swift").read_text()
(temporary / "NotchLayerFill.swift").write_text(source.split("enum NotchLayerScalarAnimation", 1)[0])
source = (root / "Sapphire/Notch/NotchHostedContentView.swift").read_text()
(temporary / "NotchHostEnvironment.swift").write_text(source.split("final class NotchGatedHostingView", 1)[0])
source = (root / "Sapphire/Notch/NotchIslandBar.swift").read_text()
start = source.index("struct NotchIslandBarButton<")
end = source.index("private struct NotchIslandBarTypeButton", start)
(temporary / "NotchIslandBarButton.swift").write_text("import SwiftUI\n" + source[start:end])
def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    level = 1
    while level:
        if source[end] == '{': level += 1
        elif source[end] == '}': level -= 1
        end += 1
    return source[start:end]
support = (root / "Sapphire/Notch/NotchViewSupport.swift").read_text()
swipe = (root / "Sapphire/Utilities/NotchSwipeRow.swift").read_text()
controls = [block(support, "struct SubtleIconButton:"), block(support, "struct BatteryInfoView:"), block(swipe, "struct NotchCapsuleIconLabel:")]
(temporary / "HeaderControls.swift").write_text("import SwiftUI\n" + "\n".join(controls))
controller = (root / "Sapphire/Notch/NotchController.swift").read_text()
assert "@ObservedObject private var appAppearance = AppAppearance.shared" in controller
assert "expandedColorScheme: expandedPanelColorScheme" in controller
assert "surfaceHeight: targetSize.height" in controller
plane = (root / "Sapphire/Notch/NotchWidgetPlane.swift").read_text()
assert plane.index(".appPanelAppearance()") < plane.index(".notchHostEnvironment(")
chrome = (root / "Sapphire/Notch/NotchExpandedChrome.swift").read_text()
assert "widgetEnvironment(piece.view).appPanelAppearance(appAppearance)" in controller
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/Services/Menubar/MenuBarWallpaperTint.swift" \
  "$REPO_ROOT/Sapphire/Notch/CustomNotchShape.swift" \
  "$REPO_ROOT/Sapphire/App Settings/AppAppearanceSettingsSection.swift" \
  "$CHECK_ROOT/NotchSurfaceStyle.swift" \
  "$CHECK_ROOT/NotchLayerFill.swift" \
  "$CHECK_ROOT/NotchHostEnvironment.swift" \
  "$CHECK_ROOT/NotchIslandBarButton.swift" \
  "$CHECK_ROOT/HeaderControls.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/SurfaceStyleFixtures.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/SurfaceStyleChecks.swift" \
  -o "$CHECK_ROOT/surface-checks"
"$CHECK_ROOT/surface-checks" "$RENDER_OUTPUT"
