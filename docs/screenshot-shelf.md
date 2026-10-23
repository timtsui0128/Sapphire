# 截图暂存架

这次改造以 Sapphire `2e80856` 为基础，把截图收集功能放进原来的刘海／File Shelf。

## 使用方式

如果已经运行了其他版本的 Sapphire，先退出，再打开本次构建的 `Sapphire.app`。

1. 启动改造后的 Sapphire，正常按 `⇧⌘4`、`⇧⌘3` 或 `⇧⌘5` 截图，并保存为文件。
2. 截图保存后会自动进入 **File Shelf → Screenshots**，无需在右下角缩略图消失前抢着拖动。
3. 连续截取 5 张后，打开文件架。新加入的截图会自动选中；点击缩略图可以取消或补选，也可以用 **Select all** 全选。
4. 按住 **Drag 5 screenshots** 拖入支持多附件的对话框。这是 5 个独立的文件，不会合成长图或压缩包。
5. 默认拖出后仍然保留。截图页右上角的齿轮可更改保留方式；也可以在 **Settings → File Shelf → Screenshots** 调整。取消拖动不会清空。

点击截图区后，支持 `⌘A` 全选、`⌘C` 复制所选文件；仅悬停打开刘海不会抢走当前应用的键盘焦点。目标应用对“粘贴多个文件”的支持不同，建议优先使用批量拖放。

## 保存与收集范围

- 新的自动收集截图会从系统保存位置移入 `~/Library/Application Support/com.cshariq.sapphire/ScreenshotShelf/`，不再留在桌面；手动导入仍然复制并保留原文件。齿轮里的 **Show Sapphire storage folder** 可以打开专用文件夹。
- 三种模式可选：**Keep until I remove** 长期保留；**Delete after 24 hours** 在 24 小时后清理；**Remove after successful drop** 被目标应用接受后从暂存架移除。设置只作用于之后的新截图和新导入，旧内容保持原有策略。
- 到期清理在 Sapphire 运行时执行；退出期间到期的内容会在下次启动时清理。成功拖出是系统拖放完成回调，不代表对话附件已经上传完成，因此实际文件有两分钟读取宽限期。复制到剪贴板不会触发“拖出后移除”。
- 默认读取 macOS 的截图保存文件夹；更改系统截图位置后会重新检测。文件夹菜单也可以手动选择位置或恢复使用系统位置。
- 首次启动只收集之后的新截图，不会扫描导入所有旧图。旧截图可通过 **Add screenshots…** 添加。
- 自动收集依据 macOS 截图元数据，不依赖英文文件名，普通下载的 PNG 不会被当作截图。
- 已收集的截图改名不会重复加入。原地编辑旧截图不算新截图；需要更新版本时可手动添加。
- 收集发生在系统实际写入文件之后，文件可能在原位置短暂出现。启用右下角浮动缩略图时，系统保存可能稍有延迟；取消或删除未保存的截图不会进入文件架。本功能不改写系统截图保存位置。
- 自动移动支持与 Sapphire 专用目录处在同一磁盘的截图。跨磁盘截图会保留原文件并显示手动导入提示。移动前记录恢复日志；保存失败或移动中断时会恢复文件，避免覆盖同名新文件。
- 按住 Control 的“仅复制到剪贴板”截图不会生成文件，目前不在自动收集范围内。
- 需要读写截图保存文件夹，不需要本功能申请屏幕录制权限。如 macOS 拒绝访问，界面会显示错误并提供重新选择文件夹的入口。
- 点击垃圾桶会移除 Sapphire 目录中的所选截图文件；对于自动收集后移入的截图，这就是当前保留的文件。手动导入的原始文件始终保留。移除后有约两分钟的读取宽限期。

## 构建与验证

主应用包含截图模块，入口在 Sapphire 原有的 **File Shelf → Screenshots**，不需要运行独立截图应用。

构建完整的公开源码版：

```sh
bash Tools/build-sapphire-public.sh
```

生成 `output/public-build/Build/Products/Debug/Sapphire.app`。构建脚本为 Xcode 26.3 生成隔离工程，使用仓库锁定的依赖版本、公开替代实现及本地 ad-hoc 签名；原始 Xcode 工程不被改写。本机产物为 Apple Silicon（arm64）版本，最低 macOS 14。

新版交付：`output/Sapphire Click.app`，压缩包为 `output/Sapphire-Notch-Click-Recovery-arm64.zip`。此前的构建产物保留，避免覆盖正在运行的程序。启动新版前请先退出当前 Sapphire。该版本同时包含[自建 Sports 与 F1 排名](community-sports.md)、[股票关注列表、统一黑色面板及蓝牙静音](community-finance-and-appearance.md)、[锁屏时隐藏和暂停](session-privacy.md)，以及[外接屏切回内置屏的窗口适配](window-fit.md)。

本版完整主应用编译、签名、压缩包解压后的签名复检均通过。隔离启动检查使用项目测试入口，只确认应用和动态库可加载；常规权限引导与当前用户的真实刘海操作由用户启动新版后完成。截图行为测试全部通过，Sports 另通过模拟网络测试、真实接口请求及两种宽度的原生离屏渲染检查。

首次启动会进入 Sapphire 原有引导流程。刘海需要其原有的辅助功能权限；截图收集本身只需读取截图保存文件夹。辅助服务步骤可选择 **Skip for now**，截图功能不依赖它。截图服务会在主应用启动后自动运行。公开仓库未包含的商业功能使用上游替代实现，本地签名版本也不能使用要求开发者签名的特权服务。

此版本是本地改装版。Sapphire 的官方更新默认可以自动下载，但安装需要手动确认；安装官方版本会覆盖这些改动。可以在 **Settings → About → Updates** 关闭自动更新检查，之后从这份源码重新构建。

以下轻量原生宿主仅供开发时独立验证：

```sh
bash Tools/build-screenshot-shelf.sh
```

生成 `output/Sapphire Screenshots.app`。它有独立窗口和菜单栏入口，使用与主应用相同的截图模块。此宿主与完整 Sapphire 使用不同的 Bundle ID，暂存数据各自独立。

自动检查：

```sh
bash Tools/ScreenshotShelfTests/run.sh
```

检查真实目录监听、五张新截图移动、旧截图与普通 PNG 排除、去重和持久保存、手动导入复制、三种保留策略、取消／接受拖放、暂停期间到期、旧清单兼容、保存失败回滚、移动中断与重名恢复，以及五个原生文件拖放条目。测试使用临时文件夹及测试图片。AppKit 剪贴板检查需要正常的 macOS 用户会话。

浏览器拖放验收：

```sh
bash Tools/run-screenshot-ui-test.sh
```

打开 `output/Screenshot Shelf UI Test.app`，把 **Drag 5 screenshots** 拖到下方本地 WebKit 测试区，应显示 **5 files received**。测试区无网络请求，使用生成的示例图片。

前一版已实际通过此窗口完成五张全选、三张部分选择的拖放，WebKit 分别收到 5 和 3 个独立 PNG 文件。本版新增策略另有自动检查；第三种模式下，只有成功拖出的所选项目会移除。各聊天产品的附件数量和格式限制仍以目标产品为准。

## 实现位置

- `Sapphire/Services/Screenshots/ScreenshotShelfManager.swift`：目录监听、截图识别、自动移动、清单与恢复日志、保留策略。
- `Sapphire/Widgets/Screenshots/ScreenshotShelfView.swift`：缩略图、选择、原生多文件拖放。
- `Sapphire/Widgets/Screenshots/ScreenshotShelfSettingsView.swift`：主设置页中的截图插件设置。
- `Sapphire/Services/Dropbox/FileShelfManager.swift`：文件架中的 Screenshots / Files 页签。
- `Sapphire/App/AppDelegate.swift`：随 Sapphire 启停收集服务。
- `Sapphire/LiveActivities/LiveActivityManager.swift`、`Sapphire/Notch/NotchController.swift`：刘海数量提示和文件架入口。
