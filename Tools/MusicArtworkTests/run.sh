#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-music-artwork.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$REPO_ROOT/output/swift-module-cache"
python3 - "$REPO_ROOT" "$CHECK_ROOT" <<'PY'
from pathlib import Path
import os, subprocess, sys
root, scratch = map(Path, sys.argv[1:])
# Exercise the production controller without launching a media stream or controlling playback.
source = (root/'Sapphire/Services/Music/NativeMediaController.swift').read_text()
if os.environ.get('SAPPHIRE_ARTWORK_BASELINE') == '1':
    source = subprocess.check_output(['git', 'show', 'HEAD:Sapphire/Services/Music/NativeMediaController.swift'], cwd=root, text=True)
source = source.replace('private var isListening', 'var isListening')
source = source.replace('private func handleTrackUpdate(', 'func handleTrackUpdate(')
(scratch/'NativeMediaController.swift').write_text(source)
policies = (root/'Sapphire/Services/Music/MusicReliabilityPolicies.swift').read_text()
(scratch/'MusicPolicies.swift').write_text(policies[:policies.index('// MARK: - Player modes from MediaRemote')])
manager = (root/'Sapphire/Services/Music/MusicManager.swift').read_text()
start = manager.index('    private func showRemoteArtwork(')
end = manager.index('    private func routeSystemPayload(', start)
methods = manager[start:end]
start = manager.index('    private func applyArtwork(')
end = manager.index('    private func refreshArtworkColorExtractionIfNeeded(', start)
methods += manager[start:end]
(scratch/'ArtworkMethods.swift').write_text('import AppKit\nimport Foundation\nextension ArtworkManagerFixture {\n' + methods.replace('private ', '') + '\n}')
# Both paths must invalidate the old cover before publishing a new track token.
boundary = manager[manager.index('        if hasTrackChanged {', manager.index('    private func applyTrackPayload(')):]
assert boundary.index('clearArtwork()') < boundary.index('self.currentTrackArtworkToken = trackIdentity')
connect = manager[manager.index('    private func syncConnectNowPlayingMetadata('):manager.index('    private func lockConnectMediaIdentity(')]
assert connect.index('currentTrackArtworkToken = track.uri') < connect.index('showRemoteArtwork(imageURL)')
PY
xcrun swiftc -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_ROOT/output/swift-module-cache" \
  "$CHECK_ROOT/MusicPolicies.swift" \
  "$REPO_ROOT/Sapphire/Services/Music/MediaApplicationIdentity.swift" \
  "$REPO_ROOT/Sapphire/Services/Music/NowPlayingAdapterIO.swift" \
  "$CHECK_ROOT/NativeMediaController.swift" \
  "$CHECK_ROOT/ArtworkMethods.swift" \
  "$REPO_ROOT/Tools/MusicArtworkTests/ArtworkManagerFixture.swift" \
  "$REPO_ROOT/Tools/MusicArtworkTests/MusicArtworkChecks.swift" \
  -o "$CHECK_ROOT/music-artwork-checks"
"$CHECK_ROOT/music-artwork-checks"
