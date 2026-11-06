#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-native-appearance.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
source = (root / 'Sapphire/Utilities/Helpers.swift').read_text()
start = source.index('struct VisualEffectView:')
end = source.index('\nextension Int {', start)
(scratch / 'VisualEffectView.swift').write_text('import AppKit\nimport SwiftUI\n' + source[start:end])
source = (root / 'Sapphire/Notch/NotchLayerSurface.swift').read_text()
(scratch / 'NotchLayerScalarAnimation.swift').write_text(source.split('// MARK: - Layer surface', 1)[0])
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/Utilities/LayerProgressViews.swift" \
  "$REPO_ROOT/Sapphire/Utilities/LayerGradientProgressRing.swift" \
  "$REPO_ROOT/Sapphire/Utilities/LayerNumericText.swift" \
  "$REPO_ROOT/Sapphire/Utilities/LiquidGlassView.swift" \
  "$REPO_ROOT/Sapphire/Notch/NotchMorphAnimation.swift" \
  "$CHECK_ROOT/NotchLayerScalarAnimation.swift" \
  "$CHECK_ROOT/VisualEffectView.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/NativeLayerChecks.swift" \
  -o "$CHECK_ROOT/check-native"
"$CHECK_ROOT/check-native" "$REPO_ROOT/output/original-ui-renders"
