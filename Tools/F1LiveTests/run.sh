#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-f1-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
xcrun swiftc \
  -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Services/CommunitySports/CommunitySportsService.swift" \
  "$REPO_ROOT/Sapphire/Services/CommunitySports/F1LiveTimingService.swift" \
  "$REPO_ROOT/Tools/F1LiveTests/F1LiveChecks.swift" \
  -o "$CHECK_ROOT/f1-live-checks"
"$CHECK_ROOT/f1-live-checks" "$@"
