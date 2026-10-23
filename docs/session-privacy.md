# 锁屏时隐藏 Sapphire

本版交付为 `output/Sapphire Click.app`，压缩包为 `output/Sapphire-Notch-Click-Recovery-arm64.zip`。先退出当前 Sapphire，再打开新版。继续使用原有设置和截图目录，包含蓝牙静音、原有界面主题、统一黑色面板、截图、F1 和股票功能，以及[外接屏切回内置屏的窗口适配](window-fit.md)。

## 行为

- 锁屏或切换到其他用户会话时，隐藏 Sapphire 的刘海、设置、歌词、启动器、小组件和辅助浮窗，停止它们的交互；旧版“锁屏显示刘海／小组件”的设置不会重新开启这些窗口。
- 锁屏时启动 Sapphire 会等待确认解锁后再显示正常界面。仅唤醒屏幕不算解锁；锁屏通知和用户会话状态分别检查，系统状态未知时先保持隐藏。
- 暂停截图及剪贴板收集。已有内容保留；解锁后重新建立基线，不补收锁屏期间的截图或剪贴板内容。锁屏前排队的异步收集和写入不会跨锁屏周期重新执行。
- 阻止快捷键、启动器手势、晚到的显示回调和后台进度浮窗重新打开界面。后台文件传输可继续完成，锁屏期间不显示它的 Sapphire 浮窗。
- 取消 Sapphire 自己的摄像头认证、镜像摄像头和待执行的密码注入；不在锁屏上启动 Face ID／蓝牙自动解锁。Mac 仍使用系统的正常解锁方式。
- 关闭 Sapphire 的锁屏壁纸窗口和锁屏音乐窗格。保存的壁纸路径、截图历史、股票关注列表等数据保留。
- 解锁回到当前用户会话后恢复刘海和收集服务。设置与歌词窗口保持隐藏，用户需要时再打开；摄像头不自动重开。

进程会保留在后台等待解锁，并非锁屏时彻底退出。此改动控制 Sapphire 自己的显示、输入和收集路径，不更改 macOS 的锁屏设置或全局权限。

## 验证

```sh
bash Tools/SessionPrivacyTests/run.sh
bash Tools/SessionPrivacyTests/check-lock-settings.sh
bash Tools/SessionPrivacyTests/run-window-routes.sh
bash Tools/ScreenshotShelfTests/run.sh
bash Tools/ClipboardPrivacyTests/run.sh
```

状态检查使用注入的系统快照和独立通知中心，覆盖锁屏启动、用户切换、乱序通知、唤醒但未解锁、延迟解锁状态、重复通知、未知状态和异步取消。原生窗口检查直接编译实际窗口类和呈现器，确认锁定时无法显示或取得焦点，排队的呈现请求及文件进度回调不会弹窗。截图／剪贴板检查使用临时目录与测试内容。没有通过测试去锁定、解锁或切换当前用户的真实会话。

核心状态位于 `Sapphire/Services/SessionPrivacy/SessionPrivacyState.swift`；主应用的启停和窗口隔离由 `AppDelegate` 接入，原生窗口、快捷键、认证与独立浮窗同时在各自入口检查该状态。
