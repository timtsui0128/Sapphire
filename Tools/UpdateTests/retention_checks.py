#!/usr/bin/env python3
"""Cleanup safety tests: disposable fixtures only; no real Trash or network access."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release", ROOT / "Tools/Updates/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
retention = release.release_retention


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.remote = []
        for build in range(1, 6):
            tag = f"personal-v0.1.{build}"
            directory = self.root / tag
            directory.mkdir()
            paths = [directory / f"TopLet-{build}.zip", directory / f"TopLet{build}-0.delta", directory / "appcast.xml"]
            for path in paths:
                path.write_text(f"fixture {build}: {path.name}")
            assets = {p.name: {"size": p.stat().st_size, "sha256": retention.digest(p)} for p in paths}
            receipt = {"tag": tag, "build": str(build), "repository": "test/repo", "public_key": "key",
                       "supports_delta_updates": True, "assets": assets}
            (directory / "release.json").write_text(json.dumps(receipt))
            self.remote.append({"tag_name": tag, "draft": False, "prerelease": False,
                                "assets": [{"name": n, "size": a["size"], "digest": "sha256:" + a["sha256"]}
                                           for n, a in assets.items()]})

    def plan(self):
        return retention.plan(self.root, self.remote, "test/repo", "key")

    def test_only_old_verified_binaries(self):
        unknown = self.root / "personal-v0.1.1/my-photos.zip"
        unknown.write_text("user data")
        items = self.plan()
        self.assertEqual(len(items), 6)
        self.assertEqual({i["release"] for i in items}, {f"personal-v0.1.{b}" for b in (1, 2, 3)})
        self.assertTrue(all(Path(i["path"]).suffix in (".zip", ".delta") for i in items))
        self.assertTrue(unknown.exists())
        with patch.object(retention, "move_to_trash") as trash:
            retention.cleanup(self.root, self.remote, "test/repo", "key")
            trash.assert_not_called()

    def test_modified_or_unverifiable_assets_stay(self):
        (self.root / "personal-v0.1.1/TopLet-1.zip").write_text("changed")
        self.remote[1]["assets"][0]["digest"] = None
        items = self.plan()
        names = {Path(i["path"]).name for i in items}
        self.assertNotIn("TopLet-1.zip", names)
        self.assertNotIn("TopLet-2.zip", names)

    def test_pending_releases_and_baselines_stay(self):
        self.remote[-1]["draft"] = True
        path = self.root / "personal-v0.1.5/release.json"
        receipt = json.loads(path.read_text())
        receipt["delta_bases"] = ["1", "2"]
        path.write_text(json.dumps(receipt))
        self.assertEqual(self.plan(), [])
        self.remote[-1]["draft"] = False
        self.remote[-1]["prerelease"] = True
        self.assertEqual(self.plan(), [])

    def test_symlinks_and_foreign_receipts_stay(self):
        path = self.root / "personal-v0.1.1/TopLet-1.zip"
        target = self.root / "untouched.zip"
        path.rename(target)
        path.symlink_to(target)
        receipt_path = self.root / "personal-v0.1.2/release.json"
        receipt = json.loads(receipt_path.read_text())
        receipt["repository"] = "different/repo"
        receipt_path.write_text(json.dumps(receipt))
        paths = {i["path"] for i in self.plan()}
        self.assertNotIn(str(path), paths)
        self.assertFalse(any("personal-v0.1.2" in p for p in paths))

    def test_changes_after_planning_abort_before_mutation(self):
        items = self.plan()
        Path(items[-1]["path"]).write_bytes(b"changed after plan")
        with patch.object(retention.subprocess, "run") as process:
            with self.assertRaises(RuntimeError):
                retention.move_to_trash(items, self.root / "report.json")
            process.assert_not_called()

    def test_staging_cleanup_on_generator_failure(self):
        source = self.root / "personal-v0.1.1/TopLet-1.zip"
        destination = self.root / "staging"
        destination.mkdir()
        original = source.read_bytes()
        with self.assertRaises(RuntimeError):
            with release.staged_baselines([{"archive": source}], destination):
                self.assertEqual((destination / source.name).read_bytes(), original)
                raise RuntimeError("simulated signing failure")
        self.assertEqual(list(destination.iterdir()), [])
        self.assertEqual(source.read_bytes(), original)
        (destination / source.name).write_text("preexisting")
        with self.assertRaises(RuntimeError):
            with release.staged_baselines([{"archive": source}], destination):
                pass
        self.assertEqual((destination / source.name).read_text(), "preexisting")


if __name__ == "__main__":
    unittest.main()
