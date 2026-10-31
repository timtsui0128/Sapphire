# TopLet: name and compatibility

The display spelling is **TopLet**. Version 0.1.8 / build 18 changes the app bundle and executable to `TopLet.app` / `TopLet`, app/menu/onboarding/settings/update text, both UI languages, README, release title and archive name. The About page links to this fork, the original project and bundled license notices.

TopLet remains based on Sapphire by Shariq Charolia and contributors and remains GNU AGPLv3. External Sapphire Browser, Sapphire VM, the phone companion, named virtual camera and helper components retain their actual names. The icon has not been redesigned in this name-only release.

## Compatibility contract

- Keep `com.cshariq.sapphire`, existing UserDefaults keys, Keychain services, shared containers, data paths, file UTIs and `sapphire:` links. No screenshot/history/settings migration or destructive reset is required.
- The default GitHub branch is `codex/personal-notched-tools`, which presents TopLet. `main` retains the upstream state.
- Keep the repository at `timtsui0128/Sapphire`, its signed appcast URL, `personal-v…` tag pattern, public signing key and update preferences domain. Old clients accept TopLet ZIP/delta asset names under the same trusted repository.
- Internal Xcode target, project path and Swift module remain `Sapphire`; `PRODUCT_NAME` is `TopLet`. Existing source build commands continue to work.
- Release receipts record the bundle filename. Delta validation reads old receipts without this field as `Sapphire.app` and new receipts as `TopLet.app`; patches are applied and signature/metadata checked before publication.
- Sparkle updates the old installed application **in place**. Its physical filename may remain `Sapphire.app`; this is not an incomplete update. New downloads contain `TopLet.app`. No automatic self-move, system permission reset or second app installation is performed.
- Releases through 0.1.9 use ad-hoc application signing, separate from Sparkle update signing. New build tooling supports a persistent Keychain certificate; see [application signing](app-updates.md#stable-application-identity-and-macos-permissions). Renaming alone does not stabilize macOS permission identity.
- To normalize an existing installation, quit the app completely first, rename the same `Sapphire.app` to `TopLet.app` in Finder, then reopen it. Do not move or rename a running app: Sparkle may retain the old installer path. Do not overwrite another existing TopLet copy.

## 简体中文

名称统一为 **TopLet**。界面、菜单、设置、关于页、更新提示、README 和新安装包使用新名；原作者署名和 AGPLv3 保留。继续使用旧标识、数据目录和更新通道，因此旧设置与截图无需搬移。旧版通过应用内更新后，Finder 文件名可能仍显示 `Sapphire.app`；应用内和“关于”页应显示 TopLet 0.1.8。新下载包包含 `TopLet.app`。不会自行搬动正在运行的应用或重置系统授权。
