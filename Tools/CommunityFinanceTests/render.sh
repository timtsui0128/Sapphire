#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RENDER_OUTPUT="${1:-"$REPO_ROOT/output/finance-renders"}"
RENDER_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-finance-render.XXXXXX")"
trap 'rm -rf "$RENDER_TEMP"' EXIT
mkdir -p "$RENDER_OUTPUT" "$REPO_ROOT/output/swift-module-cache"
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT"/Sapphire/Services/CommunityFinance/*.swift \
  "$REPO_ROOT/Sapphire/Widgets/CommunityFinance/CommunityFinanceViews.swift" \
  "$REPO_ROOT/Tools/CommunityFinanceTests/Support.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/EmbeddedWidgetRender.swift" \
  "$REPO_ROOT/Tools/CommunityFinanceTests/RenderFinance.swift" \
  -o "$RENDER_TEMP/render-finance"
"$RENDER_TEMP/render-finance" "$RENDER_OUTPUT"
