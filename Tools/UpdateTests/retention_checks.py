#!/usr/bin/env python3
"""Cleanup and temporary-baseline safety tests; disposable fixtures, no network."""
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
        self.assertEqual(len(items), 10)
        self.assertEqual({i["release"] for i in items}, {f"personal-v0.1.{b}" for b in range(1, 6)})
        self.assertTrue(all(Path(i["path"]).suffix in (".zip", ".delta") for i in items))
        self.assertTrue(unknown.exists())
        with patch.object(retention, "remove_cached_artifacts") as remove:
            retention.cleanup(self.root, self.remote, "test/repo", "key")
            remove.assert_not_called()
        retention.cleanup(self.root, self.remote, "test/repo", "key", apply=True)
        self.assertEqual(self.plan(), [])
        self.assertTrue(unknown.exists())
        self.assertEqual(len(list(self.root.glob("personal-v*/release.json"))), 5)
        self.assertEqual(len(list(self.root.glob("personal-v*/appcast.xml"))), 5)
        report = json.loads((self.root / "last-cache-cleanup.json").read_text())
        self.assertEqual(len(report["results"]), 10)

    def test_modified_or_unverifiable_assets_stay(self):
        (self.root / "personal-v0.1.1/TopLet-1.zip").write_text("changed")
        self.remote[1]["assets"][0]["digest"] = None
        items = self.plan()
        names = {Path(i["path"]).name for i in items}
        self.assertNotIn("TopLet-1.zip", names)
        self.assertNotIn("TopLet-2.zip", names)

    def test_pending_releases_stay(self):
        self.remote[-1]["draft"] = True
        path = self.root / "personal-v0.1.5/release.json"
        receipt = json.loads(path.read_text())
        receipt["delta_bases"] = ["1", "2"]
        path.write_text(json.dumps(receipt))
        self.assertEqual(len(self.plan()), 8)
        self.assertTrue(all(i["release"] != "personal-v0.1.5" for i in self.plan()))
        self.remote[-1]["draft"] = False
        self.remote[-1]["prerelease"] = True
        self.assertEqual(len(self.plan()), 8)

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
        with patch.object(Path, "unlink") as unlink:
            with self.assertRaises(RuntimeError):
                retention.remove_cached_artifacts(items, self.root / "report.json")
            unlink.assert_not_called()

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


class TemporaryBaselineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.downloads = []
        for build in (1, 2, 3):
            tag = f"personal-v0.1.{build}"
            directory = self.root / "output/releases" / tag
            directory.mkdir(parents=True)
            archive = directory / "TopLet.zip"
            archive.write_bytes(self.payload(tag))
            feed = directory / "appcast.xml"
            feed.write_text(f'<rss xmlns:s="{release.NS["s"]}"><channel><item><s:version>{build}</s:version>'
                            '<enclosure url="https://example.com/TopLet.zip"/></item></channel></rss>')
            receipt = {"tag": tag, "build": str(build), "repository": release.CONFIG["repository"],
                       "public_key": "key", "supports_delta_updates": True, "app_bundle_name": "TopLet.app",
                       "assets": {p.name: {"sha256": retention.digest(p)} for p in (archive, feed)}}
            (directory / "release.json").write_text(json.dumps(receipt))
            archive.unlink()

    @staticmethod
    def payload(tag):
        return f"exact published fixture: {tag}".encode()

    def gh(self, args, bad=False):
        self.assertEqual(args[:2], ["release", "download"])
        self.assertEqual(args[3:5], ["--repo", release.CONFIG["repository"]])
        destination = Path(args[-1]) / "TopLet.zip"
        self.downloads.append(destination)
        destination.write_bytes(b"corrupted download" if bad else self.payload(args[2]))
        return ""

    def test_missing_baselines_are_verified_and_always_temporary(self):
        with patch.object(release, "ROOT", self.root), patch.object(release, "gh", side_effect=self.gh):
            for fail in (False, True):
                try:
                    with release.temporary_delta_bases("4", "key") as bases:
                        self.assertEqual([b["build"] for b in bases], ["3", "2"])
                        for base in bases:
                            self.assertTrue(base["archive"].is_file())
                            self.assertFalse(base["archive"].is_relative_to(self.root))
                        if fail:
                            raise RuntimeError("simulated appcast failure")
                except RuntimeError:
                    self.assertTrue(fail)
                self.assertTrue(all(not path.exists() for path in self.downloads))
                self.assertFalse(list(self.root.rglob("*.zip")))

    def test_changed_download_is_rejected_and_removed(self):
        with patch.object(release, "ROOT", self.root), \
             patch.object(release, "gh", side_effect=lambda args: self.gh(args, bad=True)):
            with self.assertRaisesRegex(RuntimeError, "archive changed"):
                with release.temporary_delta_bases("4", "key"):
                    self.fail("A modified download must not be used for a delta")
        self.assertTrue(self.downloads)
        self.assertTrue(all(not path.exists() for path in self.downloads))


if __name__ == "__main__":
    unittest.main()
