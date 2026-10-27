# Quick AirDrop / 快速隔空投送

## English

Sapphire 0.1.1 adds a menu-bar AirDrop destination, inspired by [Menu Drop by Sindre Sorhus](https://sindresorhus.com/menu-drop). This is an independent implementation using AppKit's public `NSSharingService.sendViaAirDrop`; no Menu Drop code, icon, or app binary is bundled. The fork remains AGPLv3 and preserves Sapphire's original attribution.

- Drag files, folders, images, web links, or text onto Sapphire's share icon in the macOS menu bar. On newer systems it uses the AirDrop symbol; older systems use the standard share symbol.
- Click the icon for **Choose Files for AirDrop…**, **AirDrop from Clipboard**, or settings. The file chooser supports multiple files and folders.
- In **File Shelf → Screenshots**, select several screenshots and click **AirDrop** to share them together.
- Toggle the icon under **Settings → File Shelf → AirDrop in the Menu Bar**. Search settings for AirDrop, Menu Drop, or screenshots. The toggle affects the menu-bar icon; screenshot sharing remains available.

The macOS AirDrop window opens after preparation. **You choose the recipient**; Sapphire does not automatically select a device. macOS handles discovery and transfer. File selection is also useful when a system gesture intercepts a drag near the top edge.

### Files, clipboard, and privacy

The general clipboard is read only when you choose its share command. Hovering over the icon checks the drag's advertised types without reading the general clipboard. Rich text is shared as plain text. Inline clipboard/drag data is limited to 64 MiB and a batch to 512 items; save larger inline content as a file first. File-only promises that have not materialized as files/images are not supported. For a drag containing both file URLs and other representations, file URLs take priority.

Ordinary selected files and folders are passed directly to macOS. Sapphire-owned screenshots are copied into a private, per-transfer cache before sharing, so cleanup of the shelf cannot invalidate an active share. Clipboard images also become temporary files. Those files are removed when the system sharing service finishes or fails. Interrupted handoffs are retained for up to a day, then removed on a later launch. Sapphire does not run its own file-upload server or a replacement AirDrop protocol.

Opening the AirDrop picker does not count as successful sharing. Screenshot retention is applied only after the system service reports success, using the item's existing retention setting. Cancelling or failing keeps the shelf items. Other destinations retain their original drag behavior. Actual device delivery remains under macOS control.

The menu icon is hidden while the session is locked or inactive. New share commands are blocked, and queued preparation/file selection is cancelled. Transfers already handed to macOS remain under the system's control; there is no public API here to cancel them after handoff.

### Validation

`bash Tools/QuickAirDropTests/run.sh` checks actual native pasteboard parsing, multiple files, links/text/RTF/images, duplicate names, staged-file contents, retention callbacks, cancellation, unavailable services, privacy, temporary cleanup, compatible symbols, and the native drag target. Sharing sessions are injected test doubles: **no file is sent to another device by these checks**. Run the screenshot, localization, appearance, and complete app build checks as well. Device discovery and real transfers require everyday testing with the intended receiving device.

## 简体中文

Sapphire 0.1.1 加入菜单栏隔空投送入口，交互灵感来自 [Sindre Sorhus 的 Menu Drop](https://sindresorhus.com/menu-drop)。功能使用 AppKit 的公开隔空投送接口独立实现，没有打包 Menu Drop 的源码、图标或应用文件。本分支继续保留 Sapphire 原作者署名及 AGPLv3 许可证。

- 将文件、文件夹、图片、网页链接或文字拖到菜单栏的分享图标，即可打开系统隔空投送窗口。较新的系统显示 AirDrop 图标，旧系统显示标准分享图标。
- 点击图标，可以选择多个文件／文件夹，或主动分享剪贴板内容。
- 在 **File Shelf → Screenshots（文件架 → 截图）** 多选截图，再点 **AirDrop**，可以一次分享多张。
- 在 **设置 → 文件架 → 菜单栏隔空投送** 开关图标，也可以搜索 AirDrop、Menu Drop、截图或隔空投送。关闭图标后，截图页的 AirDrop 按钮仍可使用。

准备完成后，**由你在 macOS 窗口里选择接收设备**，Sapphire 不会自动指定接收人。设备发现和实际传输均由系统处理。如果顶边系统手势影响拖放，可以改用“选择文件”入口。

只有主动点击分享剪贴板时才读取系统剪贴板；悬停仅检查拖入内容声明的类型。富文本按纯文字分享。内联数据上限为 64 MiB，每批最多 512 项；较大的内容可以先保存为文件。尚未生成文件／图片、仅提供文件承诺的来源暂不支持；文件 URL 与其他表现形式混合时优先分享文件。

普通文件／文件夹直接交给系统，Sapphire 管理的截图会先复制到独立私有缓存，避免截图架清理影响正在分享的内容。剪贴板图片也会写入临时文件。系统分享结束或失败后清理临时文件；意外中断的缓存会在满一天后的启动中清理。这里没有自建上传服务器，也没有替代 AirDrop 协议。

打开设备选择窗口不算分享成功。只有系统报告成功后，才按截图原有的保存策略处理；取消或失败时保留截图。其他拖放目的地仍按原有规则处理。真实送达状态由 macOS 控制。

锁屏或会话不活跃时隐藏入口、阻止新分享，并取消尚未完成的准备和文件选择。已经交给 macOS 的传输继续由系统管理，当前公开接口无法替应用取消这些传输。

原生专项检查覆盖多文件解析、图片／链接／文字、同名截图、取消与保留策略、锁屏、不可用服务和临时文件清理。检查使用模拟分享会话，没有实际向任何设备发送文件。设备发现与真实传输仍需要在接收设备上实际体验。
