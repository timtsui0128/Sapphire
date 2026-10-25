#!/usr/bin/env python3
"""Build and sign a personal release locally; publish it only with the publish command.

The private signing key stays in the login Keychain. It is never exported or uploaded.
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = json.loads((Path(__file__).parent / "sparkle-tools.json").read_text())
TOOLS = ROOT / "output/updater-tools"
FEED = f"https://github.com/{CONFIG['repository']}/releases/latest/download/appcast.xml"
NS = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True, **kwargs)


def capture(args):
    return run(args, stdout=subprocess.PIPE, text=True).stdout.strip()


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def tools():
    archive = TOOLS / f"Sparkle-{CONFIG['version']}.tar.xz"
    TOOLS.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        partial = archive.with_suffix(".partial")
        try:
            with urllib.request.urlopen(CONFIG["url"], timeout=120) as response, partial.open("wb") as out:
                shutil.copyfileobj(response, out)
            if sha256(partial) != CONFIG["sha256"]:
                raise RuntimeError("Sparkle tools download failed SHA-256 verification")
            partial.rename(archive)
        finally:
            partial.unlink(missing_ok=True)
    if sha256(archive) != CONFIG["sha256"]:
        raise RuntimeError("Sparkle tools archive failed SHA-256 verification")
    # Re-extract the checksum-pinned official tools, preserving framework symlinks.
    run(["/usr/bin/tar", "-xJf", archive, "-C", TOOLS])
    return TOOLS / "bin"


def git_clean():
    if capture(["git", "status", "--porcelain"]):
        raise RuntimeError("Commit the complete source before preparing/publishing a release")
    return capture(["git", "rev-parse", "HEAD"])


def gh(args):
    binary = os.environ.get("SAPPHIRE_GH") or shutil.which("gh") or str(ROOT / "output/github-tools/gh")
    env = os.environ.copy()
    local_config = ROOT / "output/github-tools/config"
    if "GH_CONFIG_DIR" not in env and local_config.exists():
        env["GH_CONFIG_DIR"] = str(local_config)
    return run([binary, *args], env=env, stdout=subprocess.PIPE, text=True).stdout.strip()


def prepare(args):
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or not re.fullmatch(r"[1-9]\d*", args.build):
        raise RuntimeError("Use a numeric version (0.1.0) and a positive increasing build number (10)")
    commit = git_clean()
    tag = f"personal-v{args.version}"
    destination = ROOT / "output/releases" / tag
    if destination.exists():
        raise RuntimeError(f"Release directory already exists: {destination}")
    note_text = args.notes.resolve().read_text()
    binaries = tools()
    public_key = capture([binaries / "generate_keys", "--account", CONFIG["keychain_account"], "-p"])
    source_info = plistlib.loads((ROOT / "Sapphire/App/Info.plist").read_bytes())
    if public_key != source_info["SUPublicEDKey"]:
        raise RuntimeError("The Keychain signing key does not match this app's pinned public key")
    env = os.environ.copy()
    env["SAPPHIRE_VERSION"] = args.version
    env["SAPPHIRE_BUILD_NUMBER"] = args.build
    env.setdefault("SAPPHIRE_PACKAGE_CACHE", str(ROOT / "output/language-package-cache"))
    run(["bash", "Tools/build-sapphire-public.sh"], env=env)
    app = ROOT / "output/public-build/Build/Products/Debug/Sapphire.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {"CFBundleShortVersionString": args.version, "CFBundleVersion": args.build,
                "SUFeedURL": FEED, "SUPublicEDKey": public_key,
                "SUVerifyUpdateBeforeExtraction": True, "SURequireSignedFeed": True,
                "SUSignedFeedFailureExpirationInterval": 0,
                "CFBundleIdentifier": "com.cshariq.sapphire"}
    if any(info.get(k) != v for k, v in expected.items()):
        raise RuntimeError("Built app metadata does not match the requested signed update channel")
    run(["codesign", "--verify", "--deep", "--strict", app])
    legal = app / "Contents/Resources/Legal"
    for original, bundled in [(ROOT / "LICENSE", "LICENSE-AGPLv3.txt"),
                              (ROOT / "CREDITS.md", "CREDITS.md"),
                              (ROOT / "docs/licenses/Sparkle-LICENSE.txt", "Sparkle-LICENSE.txt")]:
        if (legal / bundled).read_bytes() != original.read_bytes():
            raise RuntimeError("The app is missing required license/attribution resources")
    architectures = capture(["lipo", "-archs", app / "Contents/MacOS/Sapphire"])
    if architectures != "arm64":
        raise RuntimeError("This personal release channel currently supports arm64 only")
    destination.mkdir(parents=True)
    archive = destination / f"Sapphire-{args.version}-arm64.zip"
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive])
    # Inline plain-text notes remain covered by the appcast signature.
    archive.with_suffix(".txt").write_text(note_text)
    prefix = f"https://github.com/{CONFIG['repository']}/releases/download/{tag}/"
    run([binaries / "generate_appcast", "--account", CONFIG["keychain_account"],
         "--download-url-prefix", prefix, "--link", f"https://github.com/{CONFIG['repository']}",
         "--embed-release-notes", "--maximum-deltas", "0", destination])
    feed = destination / "appcast.xml"
    item = ET.parse(feed).find("channel/item")
    if item is None or item.findtext("s:version", namespaces=NS) != args.build:
        raise RuntimeError("Generated appcast has the wrong build number")
    enclosure = item.find("enclosure")
    signature_key = f"{{{NS['s']}}}edSignature"
    if enclosure is None or not enclosure.get(signature_key) or enclosure.get("url") != prefix + archive.name:
        raise RuntimeError("Generated appcast lacks the expected signed archive")
    (destination / "release-notes.md").write_text(
        note_text + f"\n\nSource: https://github.com/{CONFIG['repository']}/commit/{commit}\n"
        "\nUnofficial personal fork of cshariq/Sapphire by Shariq Charolia. GNU AGPLv3.\n"
        "Apple Silicon / macOS 14+. Locally ad-hoc signed; not Apple notarized.\n")
    checksum = destination / "SHA256SUMS.txt"
    checksum.write_text("".join(f"{sha256(p)}  {p.name}\n" for p in [archive, feed]))
    assets = [archive, feed, checksum]
    receipt = {"tag": tag, "version": args.version, "build": args.build, "commit": commit,
               "repository": CONFIG["repository"], "public_key": public_key,
               "assets": {p.name: {"sha256": sha256(p), "size": p.stat().st_size} for p in assets}}
    (destination / "release.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Prepared, not published: {destination}")


def publish(args):
    directory = args.directory.resolve()
    receipt = json.loads((directory / "release.json").read_text())
    if receipt["repository"] != CONFIG["repository"] or git_clean() != receipt["commit"]:
        raise RuntimeError("The prepared release does not match this repository and current source commit")
    if not re.fullmatch(r"personal-v\d+\.\d+\.\d+", receipt["tag"]):
        raise RuntimeError("Unexpected release tag")
    assets = []
    for name, expected in receipt["assets"].items():
        if Path(name).name != name:
            raise RuntimeError("Unsafe asset name")
        path = directory / name
        if sha256(path) != expected["sha256"] or path.stat().st_size != expected["size"]:
            raise RuntimeError(f"Prepared asset changed: {name}")
        assets.append(path)
    binaries = tools()
    public_key = capture([binaries / "generate_keys", "--account", CONFIG["keychain_account"], "-p"])
    if public_key != receipt["public_key"]:
        raise RuntimeError("The prepared release uses a different signing key")
    run([binaries / "sign_update", "--account", CONFIG["keychain_account"], "--verify", directory / "appcast.xml"])
    enclosure = ET.parse(directory / "appcast.xml").find("channel/item/enclosure")
    archive = directory / Path(enclosure.get("url")).name
    run([binaries / "sign_update", "--account", CONFIG["keychain_account"], "--verify", archive,
         enclosure.get(f"{{{NS['s']}}}edSignature")])
    # Require the complete source to be publicly available before publishing binaries.
    gh(["api", f"repos/{CONFIG['repository']}/commits/{receipt['commit']}", "--jq", ".sha"])
    existing = json.loads(gh(["api", f"repos/{CONFIG['repository']}/releases?per_page=100"]))
    pending_draft = None
    for release in existing:
        if release["tag_name"] == receipt["tag"]:
            if not release["draft"]:
                raise RuntimeError("This release tag already exists; never replace a published version")
            if pending_draft is not None or release["target_commitish"] != receipt["commit"]:
                raise RuntimeError("The existing draft does not match the prepared source commit")
            pending_draft = release
        if release["draft"] or release["prerelease"]:
            continue
        for asset in release.get("assets", []):
            if asset["name"] == "appcast.xml":
                # Fetch only public metadata to reject accidental build-number rollback.
                with tempfile.TemporaryDirectory() as temp:
                    gh(["release", "download", release["tag_name"], "--repo", CONFIG["repository"],
                        "--pattern", "appcast.xml", "--dir", temp])
                    prior = ET.parse(Path(temp) / "appcast.xml").find("channel/item")
                    old_build = prior.findtext("s:version", namespaces=NS)
                    if int(receipt["build"]) <= int(old_build):
                        raise RuntimeError("A new release must have a larger build number")
    if pending_draft is None:
        gh(["release", "create", receipt["tag"], *assets, "--repo", CONFIG["repository"],
            "--target", receipt["commit"], "--title", f"Sapphire Personal {receipt['version']}",
            "--notes-file", directory / "release-notes.md", "--draft"])
    # A draft's Git tag may not exist until publication. Resolve its release ID
    # from the authenticated listing, rather than GET /releases/tags/{tag}.
    uploaded = find_prepared_draft(
        json.loads(gh(["api", f"repos/{CONFIG['repository']}/releases?per_page=100"])), receipt)
    actual = {asset["name"]: asset for asset in uploaded["assets"]}
    for name, expected in receipt["assets"].items():
        if name not in actual or actual[name]["size"] != expected["size"] or actual[name].get("digest") != "sha256:" + expected["sha256"]:
            raise RuntimeError("Uploaded assets failed verification; the release remains a draft")
    with tempfile.TemporaryDirectory() as temp:
        payload = Path(temp) / "publish.json"
        payload.write_text(json.dumps({"draft": False, "make_latest": "true"}))
        gh(["api", f"repos/{CONFIG['repository']}/releases/{uploaded['id']}",
            "--method", "PATCH", "--input", payload])
    print(f"Published: https://github.com/{CONFIG['repository']}/releases/tag/{receipt['tag']}")


def find_prepared_draft(releases, receipt):
    matches = [release for release in releases if release["tag_name"] == receipt["tag"]]
    if len(matches) != 1 or not matches[0]["draft"] or matches[0]["target_commitish"] != receipt["commit"]:
        raise RuntimeError("The uploaded draft does not uniquely match the prepared release and source")
    return matches[0]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare", help="Build, verify, package and sign locally")
    prep.add_argument("--version", required=True)
    prep.add_argument("--build", required=True)
    prep.add_argument("--notes", type=Path, required=True)
    pub = commands.add_parser("publish", help="Verify, upload a draft, then publish the prepared release")
    pub.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        prepare(args) if args.command == "prepare" else publish(args)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
