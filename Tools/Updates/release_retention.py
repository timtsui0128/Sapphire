"""Remove local binary caches only after matching the published GitHub assets."""
import hashlib
import json
import re
from pathlib import Path


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def plan(root, releases, repository, public_key):
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
    result = []
    for directory, receipt in records:
        remote = published.get(receipt["tag"])
        if remote is None:
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


def remove_cached_artifacts(items, report):
    # Only the hash-verified, published copies returned by plan() are disposable.
    # Recheck the entire batch before removing anything; never follow symlinks.
    for item in items:
        path = Path(item["path"])
        if (path.is_symlink() or path.resolve() != path or not path.is_file()
                or path.stat().st_size != item["size"] or digest(path) != item["sha256"]):
            raise RuntimeError(f"Artifact changed since cleanup was planned: {path}")
    if not items:
        return
    results = []
    report.write_text(json.dumps({"planned": items, "results": results}, indent=2) + "\n")
    try:
        for item in items:
            Path(item["path"]).unlink()
            results.append({"source": item["path"], "release": item["release"], "removed": True})
    finally:
        report.write_text(json.dumps({"planned": items, "results": results}, indent=2) + "\n")


def cleanup(root, releases, repository, public_key, apply=False):
    items = plan(root, releases, repository, public_key)
    for item in items:
        print(f"{'Remove published cache' if apply else 'Would remove published cache'}: {item['path']}")
    if apply:
        remove_cached_artifacts(items, root / "last-cache-cleanup.json")
    print(f"{'Removed' if apply else 'Planned'} {len(items)} local published artifacts "
          f"({sum(i['size'] for i in items) / 1024 ** 2:.1f} MiB); metadata retained, binaries remain on GitHub.")
