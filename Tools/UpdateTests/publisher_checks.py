#!/usr/bin/env python3
"""Exercise publication decisions with a simulated GitHub API, never real uploads.

Cryptographic validation is covered by the separate native Sparkle tests.
"""
import contextlib
import io
import importlib.util
import json
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release", ROOT / "Tools/Updates/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def check(mode):
    with tempfile.TemporaryDirectory() as temp:
        directory = Path(temp)
        commit = "a" * 40
        feed = '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://github.com/timtsui0128/Sapphire/releases/download/personal-v0.2.0/Sapphire.zip" sparkle:edSignature="fixture" /></item></channel></rss>'
        (directory / "appcast.xml").write_text(feed)
        (directory / "Sapphire.zip").write_bytes(b"simulated signed archive")
        (directory / "SHA256SUMS.txt").write_text("fixture")
        (directory / "release-notes.md").write_text("fixture")
        assets = {p.name: {"size": p.stat().st_size, "sha256": release.sha256(p)}
                  for p in [directory / name for name in ["appcast.xml", "Sapphire.zip", "SHA256SUMS.txt"]]}
        receipt = {"repository": release.CONFIG["repository"], "commit": commit,
                   "tag": "personal-v0.2.0", "version": "0.2.0", "build": "11",
                   "public_key": "fixture-public-key", "assets": assets}
        (directory / "release.json").write_text(json.dumps(receipt))
        uploaded = {"id": 123, "tag_name": receipt["tag"], "target_commitish": commit,
                    "draft": True, "prerelease": False,
                    "assets": [{"name": n, "size": a["size"], "digest": "sha256:" + a["sha256"]} for n, a in assets.items()]}
        if mode == "wrong-source":
            uploaded["target_commitish"] = "b" * 40
        if mode == "public-tag":
            uploaded["draft"] = False
        if mode == "bad-upload":
            uploaded["assets"][0]["digest"] = "sha256:" + "0" * 64
        state = {"exists": mode != "new", "published": False, "created": False}

        def gh(args):
            assert not any("/releases/tags/" in str(arg) for arg in args), "A draft tag is not a release lookup key"
            if args[:2] == ["release", "create"]:
                assert not state["exists"]
                state.update(exists=True, created=True)
                return ""
            if args[0] == "api" and "/commits/" in args[1]:
                return commit
            if args[0] == "api" and args[1].endswith("/releases?per_page=100"):
                return json.dumps([uploaded] if state["exists"] else [])
            if args[:2] == ["api", f"repos/{release.CONFIG['repository']}/releases/123"]:
                assert args[2:5] == ["--method", "PATCH", "--input"]
                assert json.loads(Path(args[5]).read_text()) == {"draft": False, "make_latest": "true"}
                state["published"] = True
                return "{}"
            raise AssertionError(f"Unexpected API call: {args}")

        with patch.object(release, "git_clean", return_value=commit), \
             patch.object(release, "tools", return_value=Path("/unused/signing-tools")), \
             patch.object(release, "capture", return_value="fixture-public-key"), \
             patch.object(release, "run"), patch.object(release, "gh", side_effect=gh):
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    release.publish(SimpleNamespace(directory=directory))
            except RuntimeError:
                assert mode in {"wrong-source", "public-tag", "bad-upload"}
            else:
                assert mode in {"new", "resume"}
        assert state["published"] == (mode in {"new", "resume"})
        assert state["created"] == (mode == "new")
        print(f"PASS: publisher {mode}")


for mode in ["new", "resume", "wrong-source", "public-tag", "bad-upload"]:
    check(mode)

with tempfile.TemporaryDirectory() as temp:
    directory = Path(temp)
    tag = "personal-v0.1.3"
    prefix = f"https://github.com/{release.CONFIG['repository']}/releases/download/{tag}/"
    feed = f'<rss xmlns:sparkle="{release.NS["s"]}"><channel><item><enclosure url="{prefix}Sapphire.zip" sparkle:edSignature="full"/><sparkle:deltas><enclosure url="{prefix}Sapphire13-12.delta" sparkle:edSignature="delta" sparkle:deltaFrom="12"/></sparkle:deltas></item></channel></rss>'
    assets = {"Sapphire.zip": {}, "Sapphire13-12.delta": {}}
    (directory / "appcast.xml").write_text(feed)
    entries = release.signed_enclosures(directory, tag, assets)
    assert [path.name for path, _ in entries] == list(assets)
    for bad in [feed.replace(prefix + "Sapphire13", "https://example.com/Sapphire13"),
                feed.replace('sparkle:edSignature="delta"', ''),
                feed.replace("Sapphire13-12.delta", "undeclared.delta")]:
        (directory / "appcast.xml").write_text(bad)
        try:
            release.signed_enclosures(directory, tag, assets)
        except RuntimeError:
            pass
        else:
            raise AssertionError("Unsafe or unsigned delta enclosure accepted")
    print("PASS: publisher validates declared, signed delta assets and rejects foreign/missing/unsigned entries")

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    for build in [10, 11, 12, 13, 14]:
        directory = root / f"output/releases/personal-v0.1.{build}"
        directory.mkdir(parents=True)
        archive = directory / "Sapphire.zip"
        archive.write_bytes(f"distributed archive {build}".encode())
        feed = directory / "appcast.xml"
        feed.write_text(f'<rss xmlns:sparkle="{release.NS["s"]}"><channel><item><sparkle:version>{build}</sparkle:version><enclosure url="https://example.com/Sapphire.zip" /></item></channel></rss>')
        receipt = {"repository": release.CONFIG["repository"], "public_key": "fixture-key", "build": str(build),
                   "supports_delta_updates": build >= 12,
                   "assets": {p.name: {"sha256": release.sha256(p)} for p in [feed, archive]}}
        (directory / "release.json").write_text(json.dumps(receipt))
    with patch.object(release, "ROOT", root):
        assert [base["build"] for base in release.delta_bases("15", "fixture-key")] == ["14", "13"]
        assert all(base["app_bundle_name"] == "Sapphire.app" for base in release.delta_bases("15", "fixture-key"))
        receipt_path = root / "output/releases/personal-v0.1.14/release.json"
        renamed = json.loads(receipt_path.read_text())
        renamed["app_bundle_name"] = "TopLet.app"
        receipt_path.write_text(json.dumps(renamed))
        assert [base["app_bundle_name"] for base in release.delta_bases("15", "fixture-key")] == ["TopLet.app", "Sapphire.app"]
        renamed["app_bundle_name"] = "../Other.app"
        receipt_path.write_text(json.dumps(renamed))
        try:
            release.delta_bases("15", "fixture-key")
        except RuntimeError:
            pass
        else:
            raise AssertionError("An unsafe baseline bundle path was accepted")
        renamed["app_bundle_name"] = "TopLet.app"
        receipt_path.write_text(json.dumps(renamed))
        assert release.delta_bases("12", "fixture-key") == [], "ZIP-only clients must not receive deltas"
        assert release.delta_bases("15", "different-key") == []
        (root / "output/releases/personal-v0.1.14/Sapphire.zip").write_bytes(b"changed")
        try:
            release.delta_bases("15", "fixture-key")
        except RuntimeError:
            pass
        else:
            raise AssertionError("A rebuilt/tampered baseline was accepted")
    print("PASS: delta baselines exclude ZIP-only builds, select the latest two compatible releases, and reject changed bytes")
    print("PASS: renamed TopLet bundles and legacy Sapphire receipts coexist; unsafe baseline bundle paths are rejected")
