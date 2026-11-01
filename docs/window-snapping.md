# Window snapping / 窗口分屏

Drag a window's title bar to the **top center of the display**, then pause for the Activation Delay configured in Settings → Snap Zones & Planes (default 0.45 seconds). The trigger is a fixed 260 × 48 point region touching the top edge; it is independent of the expanded panel's width and the invisible hover probe. Moving a window elsewhere or briefly crossing the region does not open the layouts. Once open, move to a layout and release. Command temporarily bypasses snapping; Escape cancels the current drag.

The window-movement observer only starts position sampling. Both normal entry and releasing Command use the same regional dwell check. An ordinary window drag no longer expands TopLet's host window or enables global pointer capture. Moving to another display cancels the previous display's pending trigger. File drops keep the AirDrop/Clipboard destinations.

Regression checks: `bash Tools/SnapZoneTests/run.sh` exercises production geometry and the real activation timer, including main/left/stacked display placement, quick crossings, dwell, release, cancellation, teardown and shelf-drag exclusion. Existing placement/retry and dragged-window identity tests are preserved. These tests never move a user's application window.

For manual validation after installation: move a window in the middle of the screen; briefly cross the top center; then hold it there until the layouts appear and choose a layout. Repeat after moving to the external display. Test Command/Escape cancellation and an ordinary file drop separately. Actual Accessibility approval retention requires a certificate-signed update and a subsequent window move on the user's Mac.

## Window compatibility (0.1.11)

Size and position are separate Accessibility transactions. Placement now waits for each property to settle before sending the next write, then checks the complete frame twice. Bounded retries handle a busy application or a final mouse-up reset; a new drag, revoked permission, or locked session cancels further writes. An ignored write never counts as successful placement.

Some apps animate Accessibility changes when `AXEnhancedUserInterface` is enabled. The compatibility wrapper temporarily disables that flag only when it was already enabled and neither VoiceOver nor Switch Control is active, then attempts to restore the original state on success, cancellation and failure. It avoids stacking TopLet's own smooth animation on that mode. This follows the documented compatibility issue in [Rectangle's Enhanced UI notes](https://github.com/rxhanson/Rectangle/blob/main/TerminalCommands.md#control-enhanced-ui-handling); the implementation here is independent. The Accessibility messaging timeout is set on the exact window object as well as the application object.

Errors distinguish permission denial, unavailable windows, full screen, unsupported attributes, a reported minimum size that exceeds the target, and a window that did not settle. Failure diagnostics record only status, process ID and geometry, without window titles or document URLs. Minimum-size advice requires an actual minimum-size attribute; an arbitrary failed resize is no longer treated as evidence that the layout is too small.

Regression coverage includes simulated asynchronous left and right halves, transient busy errors, ignored writes, permanent failures and scoped Enhanced UI restoration. These checks exercise the production placement algorithm with controlled window responses, not a live Chrome window. Manual acceptance still requires trying Chrome's normal window on both halves of the built-in and external displays after installing 0.1.11.

## 简体中文

拖住窗口标题栏，将鼠标移到**屏幕顶部正中**并停留后才展开分屏选项。触发区域固定为 260 × 48 点，延迟在「设置 → 吸附区域与面板 → 激活延迟」调整，默认 0.45 秒。普通移动或快速经过不会展开；展开后再移动到分屏格子并松手。Command 暂时跳过，Escape 取消本次分屏。文件拖放仍显示 AirDrop／复制到剪贴板。

自动检查覆盖不同位置的屏幕、停留、离开、松手、取消和截图文件架拖动，不会操作用户的真实窗口。固定签名的权限保留效果还需要安装后通过实际更新确认。

0.1.11 会等待每次窗口尺寸和位置操作完成，再发送下一步，并两次核对最终结果。对于开启增强辅助功能界面的应用，移动期间临时处理其缩放动画模式，结束或取消后尝试恢复；启用 VoiceOver／切换控制时不修改该状态。权限、全屏、窗口不可操作、已知最小尺寸限制和窗口未响应分别提示，避免将所有失败都解释为区域太小。

回归测试覆盖异步响应的左右半屏、短暂忙碌、忽略指令、取消和状态恢复。用户实际的 Chrome 窗口及内外接屏操作仍需安装新版后验证，不能将模拟测试通过等同于所有窗口均已兼容。
