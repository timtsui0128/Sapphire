#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-pin-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache" "$REPO_ROOT/output/pin-renders"
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
support = (root/'Sapphire/Notch/NotchViewSupport.swift').read_text()
island = (root/'Sapphire/Notch/NotchIslandBar.swift').read_text()
chrome = (root/'Sapphire/Notch/NotchExpandedChrome.swift').read_text()
stage = (root/'Sapphire/Notch/NotchStage.swift').read_text()
settings = (root/'Sapphire/Models/SettingsModel.swift').read_text()
host = (root/'Sapphire/Notch/NotchHostedContentView.swift').read_text()
# Expose the control's production action to this fixture without changing it.
pieces = [block(support, marker).replace('private func toggle()', 'func toggle()') for marker in ['struct SubtleIconButton:', 'struct NotchPinButton:']]
pieces += [block(island, 'enum NotchIslandBar {'), block(settings, 'enum NotchButtonType:'), block(stage, 'struct NotchContentKey:')]
start = island.index('struct NotchIslandBarButton<')
pieces += [island[start:island.index('private struct NotchIslandBarTypeButton', start)]]
pieces += ['enum NotchExpandedChrome {\n' + '\n'.join(block(chrome, marker) for marker in ['struct Context {', 'static func showsHeader(', 'static func key(']) + '\n}']
pieces += ['final class CachedHeader { var contentKey: NotchContentKey?; let hosting = NSHostingView(rootView: AnyView(EmptyView())); func applyFittingSizeIfNeeded() {}\n' + block(host, 'func setRootView(') + '\n}']
(scratch/'ProductionPin.swift').write_text('import SwiftUI\nimport AppKit\n'+'\n'.join(pieces))
controller = (root/'Sapphire/Notch/NotchController.swift').read_text()
delegate = (root/'Sapphire/App/AppDelegate.swift').read_text()
assert 'mouseInputGate.containsPoint' in controller and 'coordinator?.containsMousePoint(point, in: window)' in controller
assert 'container.stageView as? NotchStageView' not in controller
assert 'onEscape = { closePinnedPanel() }' in controller and '_ = closePinnedPanel()' in controller
assert 'mouseInputGate.beginMouseSequence(event)' in delegate and 'mouseInputGate.endMouseSequence(event)' in delegate
assert 'let wantsTap = isHovered &&' in controller
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Notch/NotchMouseInputGate.swift" \
  "$CHECK_ROOT/ProductionPin.swift" \
  "$REPO_ROOT/Tools/NotchPinTests/PinChecks.swift" \
  -o "$CHECK_ROOT/pin-checks"
"$CHECK_ROOT/pin-checks" "$REPO_ROOT/output/pin-renders" | tee "$CHECK_ROOT/result.log"
# Prevent an early AppKit process exit from masquerading as a passing test.
rg -q 'PASS: 80 Pin actions' "$CHECK_ROOT/result.log"
