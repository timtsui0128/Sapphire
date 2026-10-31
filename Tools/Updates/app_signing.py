#!/usr/bin/env python3
"""Select a persistent local code-signing identity without exporting private keys.

Sparkle's Ed25519 key is separate. An unavailable configured identity is an error,
never a reason to silently produce another ad-hoc build.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

CONFIG_PATH = Path(__file__).with_name('signing.local.json')


def configured_identity(environ=None, config_path=CONFIG_PATH):
    environ = os.environ if environ is None else environ
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    identity = environ.get('TOPLET_SIGNING_IDENTITY', config.get('identity', '-'))
    if identity != '-' and not re.fullmatch(r'[0-9A-Fa-f]{40}', identity):
        raise RuntimeError('TOPLET_SIGNING_IDENTITY must be the exact 40-digit certificate fingerprint, or - for ad-hoc builds')
    return identity.upper()


def signing_kind(authority):
    if authority.startswith('Apple Development:'):
        return 'apple-development'
    if authority.startswith('Developer ID Application:'):
        return 'developer-id'
    raise RuntimeError('Use an Apple Development or Developer ID Application code-signing certificate')


def preflight(identity):
    if identity == '-':
        return 'adhoc'
    result = subprocess.run(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'],
                            check=True, capture_output=True, text=True)
    for fingerprint, authority in re.findall(r'\b([A-Fa-f0-9]{40})\s+"([^"]+)"', result.stdout):
        if fingerprint.upper() == identity:
            return signing_kind(authority)
    raise RuntimeError('Configured signing certificate/private key is unavailable. Restore it or explicitly choose another identity; ad-hoc fallback is disabled.')


def inspect(app):
    result = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', '-r-', str(app)],
                            check=True, capture_output=True, text=True)
    details = result.stdout + result.stderr
    if 'Signature=adhoc' in details:
        return {'kind': 'adhoc'}
    match = re.search(r'^Authority=(.+)$', details, re.MULTILINE)
    if not match:
        raise RuntimeError('Cannot identify application signing certificate')
    kind = signing_kind(match[1])
    with tempfile.TemporaryDirectory(prefix='TopLetPublicCertificate-') as temporary:
        prefix = str(Path(temporary) / 'certificate')
        # Extract the PUBLIC certificate only. The private key stays in Keychain.
        subprocess.run(['/usr/bin/codesign', '-d', '--extract-certificates', prefix, str(app)],
                       check=True, capture_output=True)
        fingerprint = hashlib.sha1(Path(prefix + '0').read_bytes()).hexdigest().upper()
    requirement = re.search(r'^designated => (.+)$', details, re.MULTILINE)
    if not requirement or 'cdhash ' in requirement[1]:
        raise RuntimeError('Certificate-signed build still has a build-specific designated requirement')
    return {'kind': kind, 'identity': fingerprint, 'designated_requirement': requirement[1]}


def validate_continuity(previous, current):
    if previous.get('kind', 'adhoc') != 'adhoc' and (
            current.get('kind') != previous['kind']
            or current.get('designated_requirement') != previous.get('designated_requirement')):
        raise RuntimeError('Application signing identity changed since the previous release. Stop and plan the permission migration instead of silently resetting user grants.')


def description(signature):
    if signature['kind'] == 'adhoc':
        return 'Locally ad-hoc signed; not Apple notarized.'
    if signature['kind'] == 'apple-development':
        return 'Apple Development signed for personal testing; not Apple notarized.'
    return 'Developer ID signed. This build pipeline does not perform Apple notarization.'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['preflight', 'sign', 'inspect'])
    parser.add_argument('app', nargs='?', type=Path)
    args = parser.parse_args()
    if args.action == 'inspect':
        if not args.app:
            parser.error('inspect requires an app path')
        print(json.dumps(inspect(args.app), indent=2))
        return
    identity = configured_identity()
    kind = preflight(identity)
    if args.action == 'preflight':
        print(f'Application signing: {kind}')
        return
    if not args.app or not args.app.is_dir():
        parser.error('sign requires an existing app bundle')
    subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', identity, str(args.app)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
    signature = inspect(args.app)
    if signature['kind'] != kind or (identity != '-' and signature.get('identity') != identity):
        raise RuntimeError('Built app does not match the configured code-signing identity')
    print(description(signature))


if __name__ == '__main__':
    main()
