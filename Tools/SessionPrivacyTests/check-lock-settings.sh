#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PRIVACY_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-lock-settings.XXXXXX")"
trap 'rm -rf "$PRIVACY_TEMP"' EXIT

python3 - "$REPO_ROOT" "$PRIVACY_TEMP" <<'PY'
from pathlib import Path
import re
import sys
root, temporary = map(Path, sys.argv[1:])
source = (root / 'Sapphire/Models/SettingsModel.swift').read_text()
flags = [
    'lockScreenShowInfoWidget', 'lockScreenShowMainWidget',
    'lockScreenShowMiniWidgets', 'lockScreenShowNotch',
    'lockScreenLiveActivityEnabled', 'lockScreenShowMusicWhenPaused'
]
preserved = [
    'lockScreenCustomWallpaperEnabled', 'lockScreenCustomWallpaperPath',
    'lockScreenKeepWallpaperAfterUnlock', 'desktopWallpaperEnabled',
    'desktopWallpaperPath', 'bluetoothUnlockEnabled'
]
def declaration(name):
    return re.search(r'^    var ' + name + r': [^\n]+', source, re.M).group(0)
marker = '    mutating func enforceLockScreenPrivacy() {'
start = source.index(marker)
end = source.index('\n    }', start) + len('\n    }')
method = source[start:end]
swift = 'import Foundation\nstruct Fixture: Equatable {\n'
swift += '\n'.join(declaration(name) for name in flags + preserved)
swift += '\n' + method + '\n}\n'
swift += 'var settings = Fixture()\n'
for name in flags:
    swift += f'precondition(!settings.{name}, "{name} must default off")\n'
    swift += f'settings.{name} = true\n'
swift += '''settings.lockScreenCustomWallpaperEnabled = true
settings.lockScreenCustomWallpaperPath = "/fixture/lock-video.mov"
settings.lockScreenKeepWallpaperAfterUnlock = true
settings.desktopWallpaperEnabled = true
settings.desktopWallpaperPath = "/fixture/desktop.jpg"
settings.bluetoothUnlockEnabled = true
let original = settings
settings.enforceLockScreenPrivacy()
'''
for name in flags:
    swift += f'precondition(!settings.{name}, "Old {name} must be retired")\n'
for name in preserved:
    swift += f'precondition(settings.{name} == original.{name}, "Preserve {name}")\n'
swift += '''let firstPass = settings
settings.enforceLockScreenPrivacy()
precondition(settings == firstPass, "Privacy normalization must be idempotent")
print("Lock settings defaults, legacy normalization, idempotence and wallpaper/Bluetooth preservation passed")
'''
(temporary / 'check.swift').write_text(swift)
for required in [
    'loaded.enforceLockScreenPrivacy()',
    'decoded.enforceLockScreenPrivacy()',
    'importedSettings.enforceLockScreenPrivacy()'
]:
    assert required in source, f'Missing load/import/peer normalization: {required}'
pane = (root / 'Sapphire/App Settings/SettingsPanes.swift').read_text()
pane = pane[pane.index('struct LockScreenSettingsView:'):pane.index('private struct WallpaperFileRow:')]
assert all('$settings.settings.' + name not in pane for name in flags)
assert '$settings.settings.lockScreenCustomWallpaperEnabled' not in pane
assert '$settings.settings.desktopWallpaperEnabled' in pane
print('Lock Screen settings expose privacy status and desktop wallpaper only')
PY
xcrun swiftc -module-cache-path "$PRIVACY_TEMP/module-cache" "$PRIVACY_TEMP/check.swift" -o "$PRIVACY_TEMP/check"
"$PRIVACY_TEMP/check"
