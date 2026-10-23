#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-finance-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/CommunityFinance/*.swift \
  "$REPO_ROOT/Sapphire/Stubs/FinanceAPIService.swift" \
  "$REPO_ROOT/Tools/CommunityFinanceTests/Support.swift" \
  "$REPO_ROOT/Tools/CommunityFinanceTests/CommunityFinanceChecks.swift" \
  -o "$CHECK_ROOT/checks"
"$CHECK_ROOT/checks" "$@"
