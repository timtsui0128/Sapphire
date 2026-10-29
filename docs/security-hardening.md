# Security hardening / 安全加固

Version 0.1.5 addresses the three source-level findings from the local 2026-10-29 review: password arguments, plaintext music credentials and unbound Spotify OAuth callbacks. This is a focused repair, not a security certification.

0.1.5 修复了 2026-10-29 本地审查确认的三项源码问题：密码进入进程参数、音乐登录凭据明文保存、Spotify 回调未绑定登录请求。这是定向修复，不是完整安全认证。

| Area / 项目 | Behavior / 行为 |
| --- | --- |
| Mac password / Mac 密码 | `ODRecord.verifyPassword` replaces `dscl` arguments. No password is added to process arguments, environment or logs by this path. / 改用进程内 API，不通过进程参数、环境变量或日志传递。 |
| Encrypted archives / 加密压缩包 | Archive Utility collects the password. Sapphire no longer accepts an archive passphrase or supplies `--passphrase`. System extraction controls destination and progress. / 系统归档工具收取密码并管理解压位置与进度。 |
| Stored credentials / 凭据存储 | A dedicated, non-synchronizing Keychain service with `WhenUnlockedThisDeviceOnly` stores tokens/cookies. / 使用专用、不经 iCloud 同步的钥匙串条目。 |
| Migration / 迁移 | Delete legacy preference values only after a successful Keychain write. Failed migration retains the original value and retries on a later read. This means the old plaintext can remain until migration succeeds or the user signs out. / 成功写入后才删旧值；失败会保留原值以供重试，迁移成功或退出账号前旧明文可能仍存在。 |
| Failed new writes / 新写入失败 | Keep the new credential only in memory; persist a non-secret deletion marker so an older token cannot return on restart. / 新凭据仅留内存，以非敏感删除标记阻止重启恢复旧令牌。 |
| Logout / 退出账号 | Delete new/old storage, invalidate pending authorization and reject late responses. A deletion marker prevents resurrection if Keychain deletion fails. / 清除新旧存储、作废待完成登录，拦截迟到响应与删除失败后的凭据恢复。 |
| OAuth | Exact `sapphire://callback`, one matching state and code, secure randomness, S256 PKCE, 10-minute expiry, single use and generation-bound network responses. Existing legacy Spotify refresh sessions remain supported until a new PKCE login. / 严格回调、一次性 state／code、随机 PKCE、10 分钟时限及响应会话校验；兼容已有 Spotify 旧登录的刷新。 |
| AppleScript | User-derived literals escape backslash before quotes and control characters. / 用户文本先转义反斜线，再处理引号和控制字符。 |

Run `bash Tools/SecurityRegressionTests/run.sh` for fake-vault migration tests, callback cases, production token methods with controlled late responses, harmless AppleScript `return` round trips and menu-bar clearance checks. Tests do not use the real Keychain, contacts, passwords or provider accounts. OpenDirectory's production method is compiled and its empty-password path is checked; correct/incorrect real-password behavior still needs user-driven verification.

运行上述测试不会读取真实钥匙串、联系人、密码或第三方账号。OpenDirectory 生产方法已编译，并检查空密码直接拒绝；真实正确／错误密码仍需用户自行验证。

The app remains locally ad-hoc signed, without Developer ID notarization or a fully validated Hardened Runtime configuration. The development certificate available on the build Mac is not a Developer ID distribution identity. Do not interpret Sparkle Ed25519 update verification as Apple notarization. Clipboard encryption, lock-screen privacy and helper trust boundaries retain their existing designs; this work does not claim a complete audit of every dependency or privileged service.

应用仍使用本地 ad-hoc 签名，没有完成 Developer ID 公证或 Hardened Runtime 兼容性验证。构建机的开发测试证书不能替代 Developer ID 分发证书；Sparkle 更新验签也不等于 Apple 公证。本轮不代表已完整审查全部依赖或特权服务。
