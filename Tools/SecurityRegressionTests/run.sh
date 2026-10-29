#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-security.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
source = (root/'Sapphire/Services/Auth/AuthenticationManager.swift').read_text()
start=source.index('    private func verifyLoginPassword(')
end=source.index('    private func currentLoginUserName()', start)
method=source[start:end]
assert 'Process()' not in method and 'record.verifyPassword(password)' in method
(scratch/'PasswordFixture.swift').write_text('import Foundation\nimport OpenDirectory\nstruct PasswordValidationFixture {\n'+method+'\n func currentLoginUserName() -> String { "unused-test-user" }\n func verifyEmpty() -> Bool { verifyLoginPassword("") }\n}\n')
for name in ['Spotify/SpotifyOfficialAPI.swift','Spotify/SpotifyPrivateAPI.swift','TIDAL/TidalAPI.swift']:
    text=(root/'Sapphire/Services/Music'/name).read_text()
    for line in text.splitlines():
        if 'UserDefaults.standard.' in line and 'ExpiresAt' not in line:
            assert not any('forKey: '+key in line for key in ['"spotifyAccessToken"','"spotifyRefreshToken"','"tidalAccessToken"','"tidalRefreshToken"','sessionUserDefaultsKey','externalRefreshTokenKey','externalClientSecretKey']), line
archive=(root/'Sapphire/Services/Archive/ArchiveExtractor.swift').read_text()
assert '"--passphrase"' not in archive and 'Archive Utility.app' in archive
controller=(root/'Sapphire/Notch/NotchController.swift').read_text()
assert 'config.initialSize.height + expandedToolbarOffset(config: config)' in controller
assert 'toolbarTopOffset: expandedToolbarOffset(config: config)' in controller
# Compile the actual authentication methods with deterministic, suspended I/O.
for provider, class_name, end_marker in [
    ('Spotify/SpotifyOfficialAPI.swift', 'SpotifyAuthFixture', '    // MARK: - API Requests'),
    ('TIDAL/TidalAPI.swift', 'TidalAuthFixture', '    // MARK: - User'),
]:
    source = (root/'Sapphire/Services/Music'/provider).read_text()
    methods = source[source.index('    private struct TokenResponse:'):source.index(end_marker)]
    methods = methods.replace('private ', '').replace('URLSession.shared', 'transport')
    methods = methods.replace('MusicCredentialStore.shared', 'vault').replace('UserDefaults.standard', 'defaults')
    header = '''import Foundation
@MainActor final class CLASS_NAME: AuthRaceSubject {
    var loginSession = OAuthLoginSession()
    let transport = SuspendedAuthTransport()
    let defaults = MemoryDefaults()
    let fakeVault = FakeVault()
    lazy var vault = fakeVault.store(defaults)
    var accessToken: String?, refreshToken: String?, accessTokenExpiresAt: Date?
    var clientId = "fixture-client", clientSecret = "synthetic-secret"
    var redirectURI = "sapphire://callback", tokenURL = "https://fixture.invalid/token"
    var refreshTask: Task<Bool, Never>?
    var isAuthenticated = false, isPremiumUser = false
    var userProfile: String?, loginError: String?
    func cancelLogin() { loginSession.cancel() }
    func fetchUserProfile() async {}
'''.replace('CLASS_NAME', class_name)
    (scratch/(class_name+'.swift')).write_text(header + methods + '\n}\n')
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$REPO_ROOT/Sapphire/System/KeychainHelper.swift" \
  "$REPO_ROOT/Sapphire/Services/Auth/MusicCredentialStore.swift" \
  "$REPO_ROOT/Sapphire/Services/Auth/OAuthLoginSession.swift" \
  "$REPO_ROOT/Sapphire/Utilities/AppleScriptLiteral.swift" \
  "$REPO_ROOT/Sapphire/Notch/ExpandedPanelLayout.swift" \
  "$CHECK_ROOT/PasswordFixture.swift" \
  "$CHECK_ROOT/SpotifyAuthFixture.swift" \
  "$CHECK_ROOT/TidalAuthFixture.swift" \
  "$REPO_ROOT/Tools/SecurityRegressionTests/AuthRaceChecks.swift" \
  "$REPO_ROOT/Tools/SecurityRegressionTests/Checks.swift" \
  -o "$CHECK_ROOT/checks"
"$CHECK_ROOT/checks"
