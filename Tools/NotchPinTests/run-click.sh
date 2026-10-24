#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-click-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, temporary = map(Path, sys.argv[1:])
def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        end += 1
    return source[start:end]
stage = (root/'Sapphire/Notch/NotchStage.swift').read_text()
view = (root/'Sapphire/Notch/NotchStageView.swift').read_text()
morph = (root/'Sapphire/Notch/NotchMorphEngine.swift').read_text()
metrics = (root/'Sapphire/Notch/NotchDisplayMetrics.swift').read_text()
controller = (root/'Sapphire/Notch/NotchController.swift').read_text()
delegate = (root/'Sapphire/App/AppDelegate.swift').read_text()
parts = ['import AppKit\nimport SwiftUI']
parts += [block(morph, 'struct NotchMorphValues:'), block(morph, 'struct NotchMorphFrame:'), block(view, 'class NotchPassthroughView:')]
parts += ['enum NotchMorphGeometry {\n'+'\n'.join(block(morph, marker) for marker in ['static func rect(size:', 'static func shape(', 'static func path('])+'\n}']
parts += ['enum NotchDisplayMetrics {\n'+block(metrics, 'static func centeredOriginX(')+'\n}']
parts += ['extension NotchStageCoordinator {\n'+block(stage, 'func containsMousePoint(')+'\n}']
parts += [block(stage, 'struct NotchStage:')]
parts += ['extension ClickControllerFixture { func connectInput() { guard let window else { return };\n'+block(controller, '(window as? DynamicFocusWindow)?.mouseInputGate.containsPoint = ')+'\n} }']
parts += ['extension DynamicFocusWindow {\n'+block(delegate, 'func setMouseEventHandlingEnabled(')+'\n}']
methods = ['func stagePointIsInsideInteractiveRegion(', 'private func outlineContains(', 'override func hitTest(', 'override func mouseDown(', 'override func mouseDragged(', 'override func mouseUp(']
# Pick the stage hitTest, not the earlier transparent container declarations.
stage_view = view[view.index('final class NotchStageView:'):]
parts += ['extension NotchStageView {\n'+'\n'.join(block(stage_view, marker) for marker in methods)+'\n}']
(temporary/'ProductionClickRouting.swift').write_text('\n'.join(parts))
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Notch/CustomNotchShape.swift" \
  "$REPO_ROOT/Sapphire/Notch/NotchStageContainerView.swift" \
  "$REPO_ROOT/Sapphire/Notch/NotchMouseInputGate.swift" \
  "$CHECK_ROOT/ProductionClickRouting.swift" \
  "$REPO_ROOT/Tools/NotchPinTests/ClickRoutingChecks.swift" \
  -o "$CHECK_ROOT/click-checks"
"$CHECK_ROOT/click-checks" "$REPO_ROOT/output/edge-renders" | tee "$CHECK_ROOT/results.log"
rg -q 'PASS: collapsed notch native clicks expand' "$CHECK_ROOT/results.log"
