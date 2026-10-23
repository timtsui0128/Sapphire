#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-session-privacy-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Services/SessionPrivacy/SessionPrivacyState.swift" \
  "$REPO_ROOT/Tools/SessionPrivacyTests/SessionPrivacyChecks.swift" \
  -o "$CHECK_ROOT/session-privacy-checks"
"$CHECK_ROOT/session-privacy-checks"
