#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-clipboard-privacy.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
# Compile the complete production manager. Redirect only its general pasteboard to an
# isolated named native pasteboard; append checks for private asynchronous seams.
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
source = (root/'Sapphire/Services/Clipboard/ClipboardManager.swift').read_text()
source = source.replace('NSPasteboard.general', 'PrivacyFixture.pasteboard')
source += '\n' + (root/'Tools/ClipboardPrivacyTests/ClipboardPrivacyChecks.swift').read_text()
(scratch/'ClipboardManagerChecks.swift').write_text(source)
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$CHECK_ROOT/ClipboardManagerChecks.swift" \
  "$REPO_ROOT/Sapphire/Services/Clipboard/ClipboardHistoryPolicy.swift" \
  "$REPO_ROOT/Tools/ClipboardPrivacyTests/PrivacyFixtures.swift" \
  -o "$CHECK_ROOT/clipboard-privacy-checks"
"$CHECK_ROOT/clipboard-privacy-checks"
