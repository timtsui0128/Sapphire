# Window snapping / 窗口分屏

Drag a window's title bar to the **top center of the display**, then pause for the Activation Delay configured in Settings → Snap Zones & Planes (default 0.45 seconds). The trigger is a fixed 260 × 48 point region touching the top edge; it is independent of the expanded panel's width and the invisible hover probe. Moving a window elsewhere or briefly crossing the region does not open the layouts. Once open, move to a layout and release. Command temporarily bypasses snapping; Escape cancels the current drag.

The window-movement observer only starts position sampling. Both normal entry and releasing Command use the same regional dwell check. An ordinary window drag no longer expands TopLet's host window or enables global pointer capture. Moving to another display cancels the previous display's pending trigger. File drops keep the AirDrop/Clipboard destinations.

Regression checks: `bash Tools/SnapZoneTests/run.sh` exercises production geometry and the real activation timer, including main/left/stacked display placement, quick crossings, dwell, release, cancellation, teardown and shelf-drag exclusion. Existing placement/retry and dragged-window identity tests are preserved. These tests never move a user's application window.

For manual validation after installation: move a window in the middle of the screen; briefly cross the top center; then hold it there until the layouts appear and choose a layout. Repeat after moving to the external display. Test Command/Escape cancellation and an ordinary file drop separately. Actual Accessibility approval retention requires a certificate-signed update and a subsequent window move on the user's Mac.

## 简体中文

拖住窗口标题栏，将鼠标移到**屏幕顶部正中**并停留后才展开分屏选项。触发区域固定为 260 × 48 点，延迟在「设置 → 吸附区域与面板 → 激活延迟」调整，默认 0.45 秒。普通移动或快速经过不会展开；展开后再移动到分屏格子并松手。Command 暂时跳过，Escape 取消本次分屏。文件拖放仍显示 AirDrop／复制到剪贴板。

自动检查覆盖不同位置的屏幕、停留、离开、松手、取消和截图文件架拖动，不会操作用户的真实窗口。固定签名的权限保留效果还需要安装后通过实际更新确认。
