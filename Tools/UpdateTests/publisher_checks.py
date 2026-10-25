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
