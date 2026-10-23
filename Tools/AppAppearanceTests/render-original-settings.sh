#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RENDER_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-original-settings.XXXXXX")"
trap 'rm -rf "$RENDER_TEMP"' EXIT
RENDER_OUTPUT="${1:-"$REPO_ROOT/output/original-settings-renders"}"
mkdir -p "$REPO_ROOT/output/swift-module-cache" "$RENDER_OUTPUT"

# Extract unmodified production view implementations, avoiding the full app's
# device/permission services. Fixture state never reads or changes user settings.
python3 - "$REPO_ROOT" "$RENDER_TEMP" <<'PY'
from pathlib import Path
import sys
root, temporary = map(Path, sys.argv[1:])
def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    level, end = 1, opening + 1
    while level:
        if source[end] == '{': level += 1
        elif source[end] == '}': level -= 1
        end += 1
    return source[start:end]
panes = (root / 'Sapphire/App Settings/SettingsPanes.swift').read_text()
components = (root / 'Sapphire/App Settings/SettingsComponents.swift').read_text()
models = (root / 'Sapphire/Models/SettingsModel.swift').read_text()
snap = (root / 'Sapphire/Models/SnapZoneModels.swift').read_text()
source = 'import AppKit\nimport SwiftUI\n'
for name in ['IconPickerView', 'NearbyShareSettingsView', 'BluetoothSettingsView',
             'RequiredPermissionsView', 'PermissionStatusRowView']:
    source += block(panes, f'struct {name}:') + '\n'
for marker in ['struct InfoContainer:', 'struct SettingsSwitch:', 'struct SettingsRowLabel:',
               'struct ToggleRow:', 'struct SettingsContainerModifier:', 'struct SettingsSectionHeader:',
               'struct SettingsCard<', 'struct SwipeActionPickerRow<']:
    source += block(components, marker) + '\n'
source += block(models, 'enum FileDropSwipeAction:') + '\n'
for name in ['SnapZone', 'SnapLayout']:
    source += block(snap, f'struct {name}:') + '\n'
(temporary / 'OriginalSettingsViews.swift').write_text(source)
PY

xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT"/Sapphire/Services/AppAppearance/*.swift \
  "$REPO_ROOT/Sapphire/App Settings/LayoutEditorView.swift" \
  "$REPO_ROOT/Sapphire/Widgets/Shared/RoundedCard.swift" \
  "$RENDER_TEMP/OriginalSettingsViews.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/OriginalSettingsFixtures.swift" \
  "$REPO_ROOT/Tools/AppAppearanceTests/RenderOriginalSettings.swift" \
  -o "$RENDER_TEMP/render-original-settings"
"$RENDER_TEMP/render-original-settings" "$RENDER_OUTPUT" -SapphireAppAppearanceMode light
"$RENDER_TEMP/render-original-settings" "$RENDER_OUTPUT" -SapphireAppAppearanceMode dark
