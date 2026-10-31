#!/usr/bin/env python3
"""Keep update builds from silently switching back to hash-based identity."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('app_signing', ROOT / 'Tools/Updates/app_signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


def rejects(action):
    try:
        action()
    except RuntimeError:
        return
    raise AssertionError('Unsafe signing transition was accepted')


with tempfile.TemporaryDirectory() as temporary:
    config = Path(temporary) / 'signing.local.json'
    assert signing.configured_identity({}, config) == '-'
    fingerprint = 'A' * 40
    config.write_text(json.dumps({'identity': fingerprint}))
    assert signing.configured_identity({}, config) == fingerprint
    rejects(lambda: signing.configured_identity({'TOPLET_SIGNING_IDENTITY': 'Apple Development'}, config))
    with patch.object(signing.subprocess, 'run', return_value=SimpleNamespace(stdout='0 valid identities found')):
        rejects(lambda: signing.preflight(fingerprint))
    with patch.object(signing.subprocess, 'run', return_value=SimpleNamespace(
            stdout=f' 1) {fingerprint} "Apple Development: Test (TEAM)"\n')):
        assert signing.preflight(fingerprint) == 'apple-development'
    print('PASS: persistent certificate selection; missing/ambiguous identities cannot fall back to ad-hoc')

previous = {'kind': 'apple-development', 'identity': 'A' * 40,
            'designated_requirement': 'identifier "test" and anchor apple generic and certificate leaf[subject.OU] = "TEAM"'}
signing.validate_continuity({'kind': 'adhoc'}, previous)
signing.validate_continuity(previous, dict(previous))
# Renewal can retain the DR despite a new public certificate fingerprint.
signing.validate_continuity(previous, dict(previous, identity='B' * 40))
rejects(lambda: signing.validate_continuity(previous, {'kind': 'adhoc'}))
rejects(lambda: signing.validate_continuity(previous, dict(previous, kind='developer-id')))
rejects(lambda: signing.validate_continuity(previous, dict(previous, designated_requirement='cdhash new-build')))
assert 'not Apple notarized' in signing.description(previous)
print('PASS: same-identity release/renewal allowed; ad-hoc regression and identity changes rejected')
