"""Retain delta baselines; trash only byte-verified, already published artifacts."""
import hashlib
import json
import re
import subprocess
from pathlib import Path


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def plan(root, releases, repository, public_key, keep=2):
    if keep < 2:
        raise ValueError("Keep at least the two baselines needed by the next release")
    root = root.resolve()
    published = {r["tag_name"]: r for r in releases if not r["draft"] and not r["prerelease"]}
    records = []
    for path in sorted(root.glob("personal-v*/release.json")):
        if path.is_symlink() or path.parent.is_symlink():
            continue
        receipt = json.loads(path.read_text())
        tag = receipt.get("tag", "")
        if (not re.fullmatch(r"personal-v\d+\.\d+\.\d+", tag) or tag != path.parent.name
                or receipt.get("repository") != repository or receipt.get("public_key") != public_key
                or not str(receipt.get("build", "")).isdigit()):
            continue
        records.append((path.parent, receipt))
    compatible = sorted((int(r["build"]) for _, r in records
                         if r["tag"] in published and r.get("supports_delta_updates") is True), reverse=True)
    protected = set(compatible[:keep])
    # Pending/draft releases may still need their original baselines for validation.
    for _, receipt in records:
        if receipt["tag"] not in published:
            protected.update(int(b) for b in receipt.get("delta_bases", []))
    result = []
    for directory, receipt in records:
        remote = published.get(receipt["tag"])
        if remote is None or int(receipt["build"]) in protected:
            continue
        assets = {a["name"]: a for a in remote["assets"]}
        for name, expected in receipt["assets"].items():
            if Path(name).name != name or not name.endswith((".zip", ".delta")):
                continue
            path = directory / name
            if not path.is_file() or path.is_symlink():
                continue
            uploaded = assets.get(name, {})
            if (uploaded.get("size") != expected["size"]
                    or uploaded.get("digest") != "sha256:" + expected["sha256"]
                    or path.stat().st_size != expected["size"] or digest(path) != expected["sha256"]):
                continue
            result.append({"path": str(path), "size": expected["size"], "sha256": expected["sha256"],
                           "release": receipt["tag"]})
    return result


def move_to_trash(items, report):
    # Recheck immediately before mutation. Never empty Trash or follow a symlink.
    for item in items:
        path = Path(item["path"])
        if (path.is_symlink() or path.resolve() != path or not path.is_file()
                or path.stat().st_size != item["size"] or digest(path) != item["sha256"]):
            raise RuntimeError(f"Artifact changed since cleanup was planned: {path}")
    if not items:
        return
    helper = Path(__file__).with_name("trash-release-artifacts.swift")
    process = subprocess.run(["/usr/bin/swift", str(helper), *[i["path"] for i in items]],
                             text=True, capture_output=True)
    moved = [json.loads(line) for line in process.stdout.splitlines()]
    report.write_text(json.dumps({"planned": items, "results": moved}, indent=2) + "\n")
    if process.returncode:
        raise RuntimeError(f"Cleanup stopped; successful moves are recorded in {report}: {process.stderr}")


def cleanup(root, releases, repository, public_key, apply=False):
    items = plan(root, releases, repository, public_key)
    for item in items:
        print(f"{'Trash' if apply else 'Would trash'}: {item['path']}")
    if apply:
        move_to_trash(items, root / "last-cleanup.json")
    print(f"{'Moved' if apply else 'Planned'} {len(items)} published artifacts "
          f"({sum(i['size'] for i in items) / 1024 ** 2:.1f} MiB); latest two baselines and all metadata retained.")
