#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APPEARANCE_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-appearance-checks.XXXXXX")"
trap 'rm -rf "$APPEARANCE_TEMP"' EXIT
APPEARANCE_OUTPUT="${1:-"$REPO_ROOT/output/appearance-renders"}"
mkdir -p "$REPO_ROOT/output/swift-module-cache" "$APPEARANCE_OUTPUT"
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/App Settings/AppAppearanceSettingsSection.swift" \
  "$REPO_ROOT"/Sapphire/Services/Screenshots/*.swift \
  "$REPO_ROOT"/Sapphire/Widgets/Screenshots/*.swift \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/AirDropPayload.swift" \
  "$REPO_ROOT/Sapphire/Services/QuickAirDrop/QuickAirDrop.swift" \
  "$REPO_ROOT/Sapphire/Services/SessionPrivacy/SessionPrivacyState.swift" \
  "$REPO_ROOT/Tools/QuickAirDropTests/AlertFixture.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/CheckAppearance.swift" \
  -o "$APPEARANCE_TEMP/check-appearance"
# Argument-domain overrides are process-local and do not change the user's mode.
"$APPEARANCE_TEMP/check-appearance" "$APPEARANCE_OUTPUT" -SapphireAppAppearanceMode light
"$APPEARANCE_TEMP/check-appearance" "$APPEARANCE_OUTPUT" -SapphireAppAppearanceMode dark
