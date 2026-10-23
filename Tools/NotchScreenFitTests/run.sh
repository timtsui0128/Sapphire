#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-notch-fit.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache" "$REPO_ROOT/output/notch-fit-renders"
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
configuration = (root/'Sapphire/Notch/NotchConfiguration.swift').read_text()
pieces = [block(support, marker) for marker in ['struct NotchPanelViewport<', 'struct IdealSizeReader:', 'extension View {']]
pieces += [block(configuration, 'enum NotchSizing {')]
(scratch/'ProductionLayout.swift').write_text('import SwiftUI\nimport AppKit\n'+'\n'.join(pieces))
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$CHECK_ROOT/ProductionLayout.swift" \
  "$REPO_ROOT/Sapphire/Notch/NotchDisplayMetrics.swift" \
  "$REPO_ROOT/Sapphire/Notch/NotchDisplayRefreshPolicy.swift" \
  "$REPO_ROOT/Sapphire/Notch/NotchHostWindowSizer.swift" \
  "$REPO_ROOT/Sapphire/Notch/NotchStageContainerView.swift" \
  "$REPO_ROOT/Sapphire/Widgets/Weather/WeatherWidgetView.swift" \
  "$REPO_ROOT/Tools/NotchScreenFitTests/ScreenFitChecks.swift" \
  -o "$CHECK_ROOT/notch-screen-fit"
"$CHECK_ROOT/notch-screen-fit" "$REPO_ROOT/output/notch-fit-renders"
