#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-window-privacy-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
delegate = (root / 'Sapphire/App/AppDelegate.swift').read_text()
classes = delegate[delegate.index('class KeyableWindow:'):delegate.index('private struct NotchScreenSelection:')]
presenter = (root / 'Sapphire/Utilities/UserWindowSupport.swift').read_text()
presenter = presenter[presenter.index('enum UtilityWindowPresenter {'):presenter.index('@MainActor\nenum HelperAlertPresenter')]
(scratch / 'WindowRoutes.swift').write_text('import AppKit\n' + classes + '\n' + presenter)
progress = (root / 'Sapphire/Widgets/FileOperations/FileOperationProgressPresenter.swift').read_text()
progress = progress.split('private struct FileOperationProgressPopupView:', 1)[0]
progress += '\nextension FileOperationProgressPresenter { var hasPrivacyTestPanel: Bool { panel != nil } }\n'
progress += '\nstruct FileTransferTask { let isComplete: Bool }\n'
progress += '\nprivate struct FileOperationProgressPopupView: View { let state: FileOperationProgressState; var body: some View { EmptyView() } }\n'
(scratch / 'ProgressRoutes.swift').write_text(progress)
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Services/SessionPrivacy/SessionPrivacyState.swift" \
  "$CHECK_ROOT/WindowRoutes.swift" "$CHECK_ROOT/ProgressRoutes.swift" \
  "$REPO_ROOT/Tools/SessionPrivacyTests/WindowRouteChecks.swift" \
  -o "$CHECK_ROOT/window-route-checks"
"$CHECK_ROOT/window-route-checks"
