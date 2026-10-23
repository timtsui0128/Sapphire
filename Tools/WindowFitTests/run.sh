#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-window-fit.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
# Compile the real geometry and native clamping code without launching Sapphire.
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
source = (root/'Sapphire/Utilities/UserWindowSupport.swift').read_text()
start = source.index('enum UtilityWindowMetrics {')
end = source.index('\nenum UtilityWindowPresenter {', start)
(scratch/'UtilityWindowMetrics.swift').write_text('import AppKit\n'+source[start:end])
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$CHECK_ROOT/UtilityWindowMetrics.swift" \
  "$REPO_ROOT/Tools/WindowFitTests/WindowFitChecks.swift" \
  -o "$CHECK_ROOT/window-fit-checks"
"$CHECK_ROOT/window-fit-checks"
