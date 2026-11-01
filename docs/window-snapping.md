# Window snapping / 窗口分屏

Drag a window's title bar to the **center just below the menu bar**, then pause for the Activation Delay configured in Settings → Snap Zones & Planes (default 0.45 seconds). The trigger is a fixed 260 × 48 point region, 48–96 points below the top edge; it is independent of the expanded panel's width and the invisible hover probe. Moving a window elsewhere or briefly crossing the region does not open the layouts. Once open, move to a layout and release. To enter Mission Control instead, keep dragging to the physical top edge. The topmost 12 points across the display cancel pending or open layouts and hand this entire drag to macOS until mouse-up. Command temporarily bypasses snapping; Escape cancels the current drag.

The window-movement observer only starts position sampling. Both normal entry and releasing Command use the same regional dwell check. An ordinary window drag no longer expands TopLet's host window or enables global pointer capture. Moving to another display cancels the previous display's pending trigger. A system handoff survives display changes and Accessibility observer replacement; the next physical drag can activate layouts again. File drops keep the AirDrop/Clipboard destinations.

Regression checks: `bash Tools/SnapZoneTests/run.sh` exercises production geometry and the real activation timer, including main/left/stacked display placement, quick crossings, dwell, release, cancellation, teardown and shelf-drag exclusion. Existing placement/retry and dragged-window identity tests are preserved. These tests never move a user's application window.

For manual validation after installation: move a window in the middle of the screen; briefly cross the top center; then pause just below the menu bar until the layouts appear and choose a layout. Also drag straight through to the top edge, and repeat after the layouts have already opened: Mission Control should stay available without a snap on release. Repeat after moving to the external display. Test Command/Escape cancellation and an ordinary file drop separately. Actual Accessibility approval retention requires a certificate-signed update and a subsequent window move on the user's Mac.

## Window compatibility (0.1.11)

Size and position are separate Accessibility transactions. Placement now waits for each property to settle before sending the next write, then checks the complete frame twice. Bounded retries handle a busy application or a final mouse-up reset; a new drag, revoked permission, or locked session cancels further writes. An ignored write never counts as successful placement.

Some apps animate Accessibility changes when `AXEnhancedUserInterface` is enabled. The compatibility wrapper temporarily disables that flag only when it was already enabled and neither VoiceOver nor Switch Control is active, then attempts to restore the original state on success, cancellation and failure. It avoids stacking TopLet's own smooth animation on that mode. This follows the documented compatibility issue in [Rectangle's Enhanced UI notes](https://github.com/rxhanson/Rectangle/blob/main/TerminalCommands.md#control-enhanced-ui-handling); the implementation here is independent. The Accessibility messaging timeout is set on the exact window object as well as the application object.

Errors distinguish permission denial, unavailable windows, full screen, unsupported attributes, a reported minimum size that exceeds the target, and a window that did not settle. Failure diagnostics record only status, process ID and geometry, without window titles or document URLs. Minimum-size advice requires an actual minimum-size attribute; an arbitrary failed resize is no longer treated as evidence that the layout is too small.

Regression coverage includes simulated asynchronous left and right halves, transient busy errors, ignored writes, permanent failures and scoped Enhanced UI restoration. These checks exercise the production placement algorithm with controlled window responses, not a live Chrome window. Manual acceptance still requires trying Chrome's normal window on both halves of the built-in and external displays after installing 0.1.11.

## 简体中文

拖住窗口标题栏，将鼠标移到**菜单栏下方正中**并停留后才展开分屏选项。触发区域固定为 260 × 48 点，位于距离屏幕顶边 48–96 点的位置，延迟在「设置 → 吸附区域与面板 → 激活延迟」调整，默认 0.45 秒。普通移动或快速经过不会展开；展开后再移动到分屏格子并松手。继续拖到屏幕最顶边会取消分屏并让出鼠标，交给 Mission Control；松手前不会再次弹出。Command 暂时跳过，Escape 取消本次分屏。文件拖放仍显示 AirDrop／复制到剪贴板。

自动检查覆盖不同位置的屏幕、停留、离开、松手、取消和截图文件架拖动，不会操作用户的真实窗口。固定签名的权限保留效果还需要安装后通过实际更新确认。

0.1.11 会等待每次窗口尺寸和位置操作完成，再发送下一步，并两次核对最终结果。对于开启增强辅助功能界面的应用，移动期间临时处理其缩放动画模式，结束或取消后尝试恢复；启用 VoiceOver／切换控制时不修改该状态。权限、全屏、窗口不可操作、已知最小尺寸限制和窗口未响应分别提示，避免将所有失败都解释为区域太小。

回归测试覆盖异步响应的左右半屏、短暂忙碌、忽略指令、取消和状态恢复。用户实际的 Chrome 窗口及内外接屏操作仍需安装新版后验证，不能将模拟测试通过等同于所有窗口均已兼容。

## Mission Control handoff (0.1.12)

The physical top edge is reserved for the system workflow described in [Apple's Mission Control guide](https://support.apple.com/en-gb/guide/mac-help/mh35798/26/mac/26). TopLet's trigger is inset below it, with a gap between activation and handoff. Pending timers recheck the actual cursor before opening, including when the final motion callback arrives late. Releasing at the edge also cancels any stale selected zone.

Handoff clears hit regions and previews, disables mouse handling in the host, and disarms and parks the transparent hover probe. Geometry changes during the collapse cannot restore that probe. The shared handoff state lasts until the primary button is released, including when Mission Control replaces the observed app; cancelled-release state protects against delayed callbacks. File AirDrop/Clipboard routing is separate.

Validation includes production drag state and timers, inset/system-edge geometry on main/left/stacked displays, handoff before and after activation, observer replacement, release cancellation and next-drag recovery. An offscreen native-window fixture checks actual probe visibility, input disarming and restoration without moving user windows. These tests do not replace a live Mission Control drag across desktops on the user's Mac.

0.1.12 同时取消分屏预览、布局命中区域和透明鼠标区域，收起过程中的尺寸变化不会重新启用它们。让出状态跨显示器和前台应用切换保留，直到实际松手。自动检查覆盖上述状态和离屏原生窗口；实际拖入 Mission Control、把窗口放到另一个桌面的体验仍需更新后确认。


## Drag observation recovery (0.1.13)

A successfully installed global mouse monitor can remain silent during a native window move. In 0.1.12, cursor polling only ran when monitor installation failed, so the inset trigger could miss movement after the first Accessibility notification. Confirmed window drags now also sample cursor position and button state at 30 Hz, independent of hover-probe entry. Stationary positions are deduplicated; release and teardown stop this sampling. The sampler does not arm the transparent probe or expand the host window.

The native fixture reproduces the failure with a non-nil but deliberately silent event-monitor token and an offscreen cursor path outside the probe. It checks actual production hover-monitor delivery into the dwell timer, release without an event, a brief crossing, Mission Control handoff, and the next drag. The pre-fix implementation fails this check. Real-window interaction remains a separate manual acceptance step after installation.

0.1.13 修复「监听器成功创建但没有继续报告窗口拖动」时分屏无法展开的问题。只在已确认拖动窗口期间补充鼠标位置与按键采样；停留位置不重复发布，松手或结束监听后停止采样，不扩大透明鼠标区域。入口仍在菜单栏下方正中，拖到最顶边仍交给 Mission Control。测试复现了旧实现失败、新实现通过的路径；更新后仍需用真实窗口确认使用体验。
