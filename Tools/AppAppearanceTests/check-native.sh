#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-native-appearance.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
python3 - "$REPO_ROOT" "$CHECK_ROOT/VisualEffectView.swift" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / 'Sapphire/Utilities/Helpers.swift').read_text()
start = source.index('struct VisualEffectView:')
end = source.index('\nextension Int {', start)
Path(sys.argv[2]).write_text('import AppKit\nimport SwiftUI\n' + source[start:end])
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/Utilities/LayerProgressViews.swift" \
  "$REPO_ROOT/Sapphire/Utilities/LayerGradientProgressRing.swift" \
  "$REPO_ROOT/Sapphire/Utilities/LayerNumericText.swift" \
  "$CHECK_ROOT/VisualEffectView.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/NativeLayerChecks.swift" \
  -o "$CHECK_ROOT/check-native"
"$CHECK_ROOT/check-native" "$REPO_ROOT/output/original-ui-renders"
