#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-bluetooth-sound-checks.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
# Exercise the actual migration and default declarations without initializing
# SettingsModel.shared, Bluetooth hardware, or the sound player.
python3 - "$REPO_ROOT" "$CHECK_ROOT/BluetoothSoundSettings.swift" <<'PY'
from pathlib import Path
import re
import sys
root = Path(sys.argv[1])
source = (root / "Sapphire/Models/SettingsModel.swift").read_text()

def function(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

properties = []
for name in ["bluetoothNotifySound", "bluetoothSoundPreferenceVersion", "bluetoothLiveActivityEnabled"]:
    match = re.search(r"^\s*var " + name + r": [^\n]+", source, re.MULTILINE)
    assert match, name
    properties.append(match.group(0).strip())
normalize = function("mutating func normalizeCollectionOrders()")
assert "migrateBluetoothConnectionSoundPreference()" in normalize
reset = function("func resetAllSettings()")
assert "resetSettings.normalizeCollectionOrders()" in reset
for signature in ["static func decodeFromPayloadReportingTolerance(", "private static func decodeFromJSONDictionary("]:
    assert "settings.normalizeCollectionOrders()" in function(signature), signature
assert "importedSettings.normalizeCollectionOrders()" in function("func importSettings(from url:")
assert "loaded.normalizeCollectionOrders()" in function("private static func readSettingsFromStorage()")
manager = (root / "Sapphire/Services/Bluetooth/BluetoothManager.swift").read_text()
assert manager.count("if SettingsModel.shared.current.bluetoothNotifySound") == 2
assert "eventType: .connected" in manager and "eventType: .disconnected" in manager
body = "\n".join(properties + [function("mutating func migrateBluetoothConnectionSoundPreference()")])
Path(sys.argv[2]).write_text("import Foundation\nstruct Settings: Codable {\n" + body + "\n}\n")
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$CHECK_ROOT/BluetoothSoundSettings.swift" \
  "$REPO_ROOT/Tools/BluetoothSoundTests/BluetoothSoundChecks.swift" \
  -o "$CHECK_ROOT/bluetooth-sound-checks"
"$CHECK_ROOT/bluetooth-sound-checks"
