#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-sports-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
# Compile the real legacy model declarations without unrelated app dependencies.
python3 - "$REPO_ROOT" "$CHECK_ROOT/LegacySportsModels.swift" <<'PY'
import pathlib, sys
source = (pathlib.Path(sys.argv[1]) / "Sapphire/Models/AppModels.swift").read_text()
start = source.index("struct SportsPayload:")
end = source.index("struct FinancePayload:", start)
pathlib.Path(sys.argv[2]).write_text("import Foundation\n" + source[start:end])
PY
xcrun swiftc \
  -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Services/CommunitySports/CommunitySportsService.swift" \
  "$REPO_ROOT/Sapphire/Stubs/SubscriptionCore.swift" \
  "$REPO_ROOT/Sapphire/Stubs/SportsAPIService.swift" \
  "$CHECK_ROOT/LegacySportsModels.swift" \
  "$REPO_ROOT/Tools/CommunitySportsTests/CommunitySportsChecks.swift" \
  -o "$CHECK_ROOT/community-sports-checks"
"$CHECK_ROOT/community-sports-checks" "$@"
