# In-app updates / 应用内更新

Personal release **0.1.0 (build 10)** introduces the personal fork's own update channel.

## Using updates

Install the first update-enabled app once, then open **Settings → About → Updates**.

- **Automatic update checks** is enabled by default. Sparkle checks on its own schedule, approximately every five hours; **Check for Updates** checks immediately.
- **Prepare updates automatically** is a new, separate opt-in, disabled by default. It downloads, verifies, and prepares a new version in the background. A prepared version can be installed with **Install and Relaunch**, or will install when you next quit Sapphire. **Cancel Prepared Update** discards that staged installation.
- Without automatic preparation, choose **Download Update** first. Installation uses Sparkle's installer; it does not run an archive's shell scripts or the public build's placeholder privileged helper.
- Settings, screenshots, and watchlists are outside the replaced app bundle and are preserved. The fork still shares the upstream Bundle ID and data directories; quit other Sapphire copies before using it.
- The app only accepts stable, signed personal releases from `timtsui0128/Sapphire`. Original upstream releases are not offered. This is periodic checking while the app runs, not a remote service that wakes a closed app.
- Session locking blocks checks and user actions, cancels pending downloads/offers and staged update replies, and suppresses update UI. If locking occurs during extraction, the ready-to-install callback cancels the prepared update.

This first channel publishes full Apple Silicon ZIP updates for macOS 14+. Version 0.1.2 (build 12) enables incremental updates between compatible builds; Intel releases are not enabled yet. Builds 10/11 require one full update because their URL policy rejects delta files. Downloads are managed inside the updater; they do not require manually downloading and replacing the app. These personal builds use local ad-hoc code signing, not Apple Developer ID notarization. Update archive signing is separate and is required even for these local builds.

## Security and source

- Sparkle **2.10.1** is pinned in the Xcode project and Swift Package lockfile.
- The public Ed25519 key is embedded in `Info.plist`. The private key is in the maintainer's login Keychain, under the Sparkle account `timtsui0128.Sapphire.Personal`; it is not in Git, the app, Release assets, or GitHub Actions secrets.
- `SUVerifyUpdateBeforeExtraction` and `SURequireSignedFeed` are enabled. Signature failure expiration is disabled (`0`), so an invalid feed never becomes acceptable merely by waiting.
- The feed URL is fixed by the updater delegate to this fork's release channel. Archive URLs must belong to this repository's `personal-v…` GitHub Release path over HTTPS. No user-defaults feed override is used.
- Sparkle validates signatures and candidate bundles and performs installation. The inherited custom updater is compiled only for the original full-build configuration; public personal builds cannot use its upstream download/install path.
- Sparkle preferences use a separate defaults domain. The older download-only preference is deliberately not migrated into automatic preparation, which can install on quit.
- Every binary release names its complete source commit. Original attribution, AGPLv3, and third-party notices remain in the repository. Sparkle's notices are preserved in `CREDITS.md`, `docs/licenses/`, and its embedded framework. The build script also bundles the original AGPLv3 license, credits, and Sparkle notices under `Contents/Resources/Legal` before code signing.

Keep the signing Keychain backed up. Losing this key prevents existing installs from accepting new signed feeds; it may require another manual bootstrap installation. Do not generate a replacement key for an existing channel casually. Anyone making a separate fork should create their own key and feed before distributing it.

## Maintainer release workflow

Commit all source changes and run the relevant tests. The first release uses `0.1.0` / build `10`; use a larger build number for every subsequent release. Tags are `personal-vVERSION`.

```sh
# Example for the next version, after committing its complete source:
python3 Tools/Updates/release.py prepare \
  --version 0.1.3 --build 13 --notes docs/releases/0.1.3.md
```

`prepare` downloads checksum-pinned official Sparkle tools, verifies the Keychain public key, builds the app, verifies metadata and its bundle signature, creates a ZIP preserving symlinks, and uses Sparkle's official `generate_appcast` to sign the archive and feed. It only writes under ignored `output/` and does not publish anything. It produces `output/releases/personal-vVERSION/` with the ZIP, signed `appcast.xml`, checksums, release notes, and a local receipt binding the assets to the source commit.

Push that source commit to this repository using Git, then publish the prepared package:

```sh
python3 Tools/Updates/release.py publish output/releases/personal-v0.1.3
```

`publish` verifies the unchanged source commit, hashes, signatures, remote source availability, and increasing build number. It uploads a draft Release, verifies every full/delta enclosure signature, checks uploaded asset sizes and GitHub SHA-256 digests, and only then publishes it as the latest release. It refuses to overwrite an existing published tag. If a failed upload leaves a draft with the same source commit and identical verified assets, rerun `publish` to resume it. A mismatched or incomplete draft stops publication and must be inspected before deleting/re-preparing it. Publishing a Git commit alone does not release an app update. No separate paid server or background CI signing service is required.

Each release provides a single current signed feed with a full ZIP fallback. The release tool automatically considers the two latest retained, delta-capable release receipts, checks unchanged baseline hashes, generates signed patches, and applies each patch locally before publishing. Keep the actual distributed archives and receipts under `output/releases/`; rebuilding an older version is not an equivalent baseline. Builds 10/11 are excluded from delta generation, so their first update still downloads the full ZIP. Future compatible updates can transfer only changed content. If a delta does not apply, Sparkle falls back to the full archive. Download size varies with the actual changes and network speed still depends on GitHub. Rollout groups, beta channels, and OS-specific branches are future work.

## Validation

```sh
python3 Tools/UpdateTests/run.py
python3 Tools/UpdateTests/publisher_checks.py
bash Tools/LocalizationTests/run.sh
bash Tools/build-sapphire-public.sh
```

The update tests build disposable native applications using the production user driver, an ephemeral signing key, and a loopback feed. They actually download, replace, and relaunch a test app, check installation on quit, cancel a prepared update, simulate privacy suppression, and reject tampered archives/feeds while preserving the old app. The release preparation separately checks the app’s Bundle ID, version, architecture, and pinned update keys. They never launch/replace the installed Sapphire app or alter the production feed/signing key. The tests additionally exercise URL restrictions, single-use callbacks, download cancellation, and progress clamping. They do not cover every disk/permissions failure, Developer ID/notarization, or every macOS release.

## 中文使用说明

首次需要安装一次带更新器的新版本，之后进入 **设置 → 关于 → 更新**：

- 默认自动检查新版，也可以手动点“检查更新”。
- “自动准备更新”默认关闭，需要单独开启。开启后在后台下载、验证并准备新版；可以点“安装并重新启动”，也可以在下次退出 Sapphire 时自动安装。
- 未开启自动准备时，先点“下载更新”。“取消已准备的更新”可以撤销已准备好的安装。
- 更新只替换应用，保留已有设置、截图和关注列表。请先退出其他 Sapphire 副本。
- 更新源只连接自己的 GitHub，原作者的更新不会覆盖这个改装版。更新列表和安装包都需要匹配内置公钥的签名；私钥留在本机钥匙串中。
- 当前提供 Apple Silicon / macOS 14+ 的完整包，以及兼容版本之间的增量包；尚未提供 Intel 发布。0.1.0／0.1.1 的更新器不接受增量 URL，需要先完整更新一次到 0.1.2，之后的兼容更新才能下载变化部分；补丁失败时回退完整包。发布工具自动从本地保留的最近两个兼容版本生成补丁，并在发布前实际应用验证。请保留原发布 ZIP 和 receipt，不要通过重新编译旧版代替。下载页显示已下载大小和平均速度，实际速度仍受 GitHub 网络影响。
- 锁屏时禁止更新界面和操作，并取消可取消的下载／安装准备；不会为了提醒新版而在锁屏上弹出窗口。

维护者以后运行上面的 `prepare` 命令构建并签名，再推送源码并运行 `publish` 发布。仅上传源码不会触发更新。此版本仍为本机 ad-hoc 签名，尚未进行 Apple Developer ID 公证；更新包的签名验证已独立启用。
