#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-language.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
APP_ROOT="$CHECK_ROOT/LanguageChecks.app/Contents"
mkdir -p "$APP_ROOT/MacOS" "$APP_ROOT/Resources" "$REPO_ROOT/output/swift-module-cache" "$REPO_ROOT/output/localization/renders"
python3 "$REPO_ROOT/Tools/LocalizationTests/audit.py"
cat > "$APP_ROOT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>language-checks</string>
<key>CFBundleIdentifier</key><string>local.sapphire.language-checks</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun xcstringstool compile --output-directory "$APP_ROOT/Resources" "$REPO_ROOT/Sapphire/Resources/Localizable.xcstrings"
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
source = (root / 'Sapphire/Utilities/UserWindowSupport.swift').read_text()
start = source.index('enum SapphireStandardMenu {')
end = source.index('\nenum UtilityWindowMetrics {', start)
(scratch / 'SapphireStandardMenu.swift').write_text('import AppKit\n' + source[start:end])
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/Services/AppAppearance/AppLanguage.swift" \
  "$REPO_ROOT/Sapphire/Services/AppAppearance/AppAppearance.swift" \
  "$REPO_ROOT"/Sapphire/Services/Screenshots/*.swift \
  "$REPO_ROOT/Sapphire/App Settings/AppAppearanceSettingsSection.swift" \
  "$CHECK_ROOT/SapphireStandardMenu.swift" \
  "$REPO_ROOT/Tools/LocalizationTests/LanguageChecks.swift" \
  -o "$APP_ROOT/MacOS/language-checks"
"$APP_ROOT/MacOS/language-checks" "$REPO_ROOT/output/localization/renders"
