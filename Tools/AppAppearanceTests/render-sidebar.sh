#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIDEBAR_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-sidebar-render.XXXXXX")"
trap 'rm -rf "$SIDEBAR_TEMP"' EXIT
SIDEBAR_OUTPUT="${1:-"$REPO_ROOT/output/appearance-renders"}"
mkdir -p "$REPO_ROOT/output/swift-module-cache" "$SIDEBAR_OUTPUT"

# Use production sidebar, labels, icons, search, and common row implementations;
# omit unrelated SettingsModel services from this isolated visual check.
python3 - "$REPO_ROOT" "$SIDEBAR_TEMP" <<'PY'
from pathlib import Path
import sys
root, temporary = map(Path, sys.argv[1:])
model = (root / "Sapphire/Models/SettingsModel.swift").read_text()
components = (root / "Sapphire/App Settings/SettingsComponents.swift").read_text()
def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    level = 1
    end = opening + 1
    while level:
        if source[end] == "{": level += 1
        elif source[end] == "}": level -= 1
        end += 1
    return source[start:end]
section = block(model, "enum SettingsSection:")
case_line = next(line for line in section.splitlines() if line.strip().startswith("case "))
properties = "\n".join(block(section, f"var {name}:") for name in [
    "id", "requiredPremiumFeature", "isBeta", "shortDescription", "searchTokens",
    "label", "systemImage", "iconGradientColors"
])
fixture = "import SwiftUI\n"
fixture += "enum SettingsAssistant { static let isSupported = false }\n"
fixture += "enum SettingsSection: String, CaseIterable, Identifiable {\n" + case_line + "\n" + properties + "\n}\n"
for name in ["InfoContainer", "SettingsSwitch", "SettingsRowLabel", "SettingsIconBadge", "ReorderHandle", "IconToggleRow", "ClearableSearchField", "SettingsContainerModifier"]:
    fixture += block(components, f"struct {name}:") + "\n"
(temporary / "SidebarDependencies.swift").write_text(fixture)
PY

xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/App Settings/AppAppearanceSettingsSection.swift" \
  "$REPO_ROOT/Sapphire/App Settings/SettingsSidebar.swift" \
  "$REPO_ROOT/Sapphire/Widgets/Shared/RoundedCard.swift" \
  "$REPO_ROOT/Sapphire/Stubs/SubscriptionCore.swift" \
  "$SIDEBAR_TEMP/SidebarDependencies.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/RenderSidebar.swift" \
  -o "$SIDEBAR_TEMP/render-sidebar"
"$SIDEBAR_TEMP/render-sidebar" "$SIDEBAR_OUTPUT" -SapphireAppAppearanceMode light
"$SIDEBAR_TEMP/render-sidebar" "$SIDEBAR_OUTPUT" -SapphireAppAppearanceMode dark
