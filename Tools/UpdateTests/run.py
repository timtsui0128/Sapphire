#!/usr/bin/env python3
"""Native Sparkle tests using disposable app bundles and a loopback-only feed.

No production app is launched, replaced, or given a test feed. Test signing keys
are ephemeral files; the production Keychain signing key is never accessed.
"""
import base64
import functools
import http.server
import json
import os
import plistlib
import secrets
import shutil
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release", ROOT / "Tools/Updates/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    requests = []
    def do_GET(self):
        self.requests.append(self.path)
        super().do_GET()

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix="SapphireUpdateTests-") as temp:
    root = Path(temp)
    tools = release.tools()
    key = root / "ephemeral-key"
    key.write_text(base64.b64encode(secrets.token_bytes(32)).decode())
    key.chmod(0o600)
    # CryptoKit derives the matching public key without storing it in any Keychain.
    derive = root / "derive.swift"
    derive.write_text('import CryptoKit\nimport Foundation\nlet seed = Data(base64Encoded: try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8))!\nprint(try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation.base64EncodedString())\n')
    public_key = run(["swift", derive, key], stdout=subprocess.PIPE, text=True).stdout.strip()
    shared = (ROOT / "Sapphire/App Settings/UpdateChecker.swift").read_text().split("private struct PersistedAvailableUpdate:")[0]
    (root / "SharedTypes.swift").write_text(shared)
    executable = root / "UpdateHarness"
    framework = ROOT / "output/updater-tools/Sparkle.framework"
    run(["swiftc", "-F", framework.parent, "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
         root / "SharedTypes.swift", ROOT / "Tools/UpdateTests/Fixtures.swift",
         ROOT / "Sapphire/Services/Updates/SparkleUpdateChecker.swift", ROOT / "Tools/UpdateTests/UpdateHarness.swift", "-o", executable])
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(root)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    origin = f"http://127.0.0.1:{server.server_port}"
    results = []
    try:
        modes = ["install", "automatic", "quit", "cancel", "lock", "bad-archive", "bad-feed", "delta", "delta-fallback", "rename"]
        if os.environ.get("TOPLET_UPDATE_TEST_MODE"):
            modes = [os.environ["TOPLET_UPDATE_TEST_MODE"]]
            assert modes[0] in {"install", "automatic", "quit", "cancel", "lock", "bad-archive", "bad-feed", "delta", "delta-fallback", "rename"}
        for mode in modes:
            case = root / mode
            downloads = case / "downloads"
            downloads.mkdir(parents=True)
            result = case / "result.json"
            app = case / "installed" / ("Sapphire.app" if mode == "rename" else "UpdateCheck.app")
            candidate = case / "candidate" / ("TopLet.app" if mode == "rename" else "UpdateCheck.app")
            payload = secrets.token_bytes(1024 * 1024) if mode.startswith("delta") else None
            for bundle, build in [(app, "1"), (candidate, "2")]:
                (bundle / "Contents/MacOS").mkdir(parents=True)
                (bundle / "Contents/Frameworks").mkdir()
                if payload is not None:
                    (bundle / "Contents/Resources").mkdir()
                    (bundle / "Contents/Resources/unchanged-fixture.bin").write_bytes(payload)
                executable_name = "TopLetFixture" if mode == "rename" and build == "2" else "UpdateHarness"
                shutil.copy2(executable, bundle / "Contents/MacOS" / executable_name)
                shutil.copytree(framework, bundle / "Contents/Frameworks/Sparkle.framework", symlinks=True)
                info = {"CFBundleIdentifier": f"local.sapphire.update-tests.{mode}.{secrets.token_hex(4)}" if build == "1" else bundle_id,
                        "CFBundleName": bundle.stem, "CFBundleDisplayName": bundle.stem,
                        "CFBundleExecutable": executable_name, "CFBundlePackageType": "APPL",
                        "CFBundleVersion": build, "CFBundleShortVersionString": f"0.{build}.0", "LSUIElement": True,
                        "LSMinimumSystemVersion": "14.0", "SUFeedURL": f"{origin}/{mode}/downloads/appcast.xml",
                        "SUPublicEDKey": public_key, "SUVerifyUpdateBeforeExtraction": True,
                        "SURequireSignedFeed": True, "SUSignedFeedFailureExpirationInterval": 0,
                        "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False,
                        "SUAllowsAutomaticUpdates": False, "TestMode": mode, "TestResult": str(result),
                        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True, "NSAllowsArbitraryLoads": True}}
                bundle_id = info["CFBundleIdentifier"]
                (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
                run(["codesign", "--force", "--deep", "--sign", "-", bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            archive = downloads / "UpdateCheck.zip"
            run(["ditto", "-c", "-k", "--keepParent", candidate, archive])
            if payload is not None:
                run(["ditto", "-c", "-k", "--keepParent", app, downloads / "UpdateCheck-old.zip"])
            run([tools / "generate_appcast", "--ed-key-file", key, "--download-url-prefix", f"{origin}/{mode}/downloads/",
                 "--versions", "2", "--maximum-versions", "1", "--maximum-deltas", "1" if payload else "0", downloads], stdout=subprocess.DEVNULL)
            feed = downloads / "appcast.xml"
            run([tools / "sign_update", "--ed-key-file", key, "--verify", feed], stdout=subprocess.DEVNULL)
            if payload is not None:
                item = ET.parse(feed).find("channel/item")
                enclosure = item.find("s:deltas/enclosure", release.NS)
                assert enclosure is not None, "The fixture must produce a signed delta"
                delta = downloads / Path(enclosure.get("url")).name
                assert delta.stat().st_size < archive.stat().st_size // 4
                run([tools / "sign_update", "--ed-key-file", key, "--verify", delta,
                     enclosure.get(f"{{{release.NS['s']}}}edSignature")], stdout=subprocess.DEVNULL)
                if mode == "delta-fallback":
                    content = bytearray(delta.read_bytes())
                    content[len(content) // 2] ^= 1
                    delta.write_bytes(content)
            if mode == "bad-archive":
                content = bytearray(archive.read_bytes())
                content[len(content) // 2] ^= 1
                archive.write_bytes(content)
            elif mode == "bad-feed":
                feed.write_bytes(feed.read_bytes().replace(b"<title>", b"<title>tampered-", 1))
            with (case / "process.log").open("w") as log:
                process = subprocess.Popen([str(app / "Contents/MacOS/UpdateHarness")], stdout=log, stderr=log)
                deadline = time.monotonic() + 65
                expected = "relaunched" if mode in {"install", "automatic", "delta", "delta-fallback", "rename"} else "rejected" if mode.startswith("bad-") else "cancelled"
                data = {}
                while time.monotonic() < deadline:
                    if result.exists():
                        data = json.loads(result.read_text())
                        if mode == "quit" and data["state"] == "ready":
                            live_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
                            if live_info["CFBundleVersion"] == "2":
                                data["state"] = "installed-on-quit"
                                expected = "installed-on-quit"
                                break
                        if data["state"] in {expected, "timeout", "rejected"}:
                            break
                    time.sleep(0.1)
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
            if data.get("state") != expected:
                raise AssertionError(f"{mode}: {data}\n{(case / 'process.log').read_text()[-10000:]}")
            installed_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            assert installed_info["CFBundleVersion"] == ("2" if mode in {"install", "automatic", "quit", "delta", "delta-fallback", "rename"} else "1")
            if mode == "rename":
                assert installed_info["CFBundleName"] == installed_info["CFBundleDisplayName"] == "TopLet"
                assert installed_info["CFBundleExecutable"] == "TopLetFixture"
                assert app.name == "Sapphire.app" and not (app.parent / "TopLet.app").exists()
                print("PASS: renamed bundle/executable installs in place, relaunches under TopLet, and retains existing preferences")
            if payload is not None:
                requested = [path for path in QuietHandler.requests if path.startswith(f"/{mode}/downloads/")]
                assert any(path.endswith(".delta") for path in requested), requested
                assert any(path.endswith("/UpdateCheck.zip") for path in requested) == (mode == "delta-fallback"), requested
                print(f"PASS: {mode} downloaded the delta; full archive fallback = {mode == 'delta-fallback'}")
            run(["codesign", "--verify", "--deep", "--strict", app])
            results.append({"case": mode, "state": data["state"], "build": installed_info["CFBundleVersion"], "message": data["message"]})
            print(f"PASS: {mode} → {data['state']}; installed build {installed_info['CFBundleVersion']}", flush=True)
            subprocess.run(["defaults", "delete", bundle_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        server.shutdown()
        server.server_close()
    output = ROOT / "output/updates/native-results.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(results, indent=2) + "\n")
    print("PASS: personal-only URL policy, single-use replies, download cancellation, lock suppression, and quit behavior")
