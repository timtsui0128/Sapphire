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
        for mode in ["install", "automatic", "quit", "cancel", "lock", "bad-archive", "bad-feed"]:
            case = root / mode
            downloads = case / "downloads"
            downloads.mkdir(parents=True)
            result = case / "result.json"
            app = case / "installed/UpdateCheck.app"
            candidate = case / "candidate/UpdateCheck.app"
            for bundle, build in [(app, "1"), (candidate, "2")]:
                (bundle / "Contents/MacOS").mkdir(parents=True)
                (bundle / "Contents/Frameworks").mkdir()
                shutil.copy2(executable, bundle / "Contents/MacOS/UpdateHarness")
                shutil.copytree(framework, bundle / "Contents/Frameworks/Sparkle.framework", symlinks=True)
                info = {"CFBundleIdentifier": f"local.sapphire.update-tests.{mode}.{secrets.token_hex(4)}" if build == "1" else bundle_id,
                        "CFBundleName": "UpdateCheck", "CFBundleExecutable": "UpdateHarness", "CFBundlePackageType": "APPL",
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
            run([tools / "generate_appcast", "--ed-key-file", key, "--download-url-prefix", f"{origin}/{mode}/downloads/",
                 "--maximum-deltas", "0", downloads], stdout=subprocess.DEVNULL)
            feed = downloads / "appcast.xml"
            run([tools / "sign_update", "--ed-key-file", key, "--verify", feed], stdout=subprocess.DEVNULL)
            if mode == "bad-archive":
                content = bytearray(archive.read_bytes())
                content[len(content) // 2] ^= 1
                archive.write_bytes(content)
            elif mode == "bad-feed":
                feed.write_bytes(feed.read_bytes().replace(b"<title>", b"<title>tampered-", 1))
            with (case / "process.log").open("w") as log:
                process = subprocess.Popen([str(app / "Contents/MacOS/UpdateHarness")], stdout=log, stderr=log)
                deadline = time.monotonic() + 65
                expected = "relaunched" if mode in {"install", "automatic"} else "rejected" if mode.startswith("bad-") else "cancelled"
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
            assert installed_info["CFBundleVersion"] == ("2" if mode in {"install", "automatic", "quit"} else "1")
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
