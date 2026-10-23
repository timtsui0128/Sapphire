# Pin 状态与点击修复

交付为 `output/Sapphire Click.app`，压缩包为 `output/Sapphire-Notch-Click-Recovery-arm64.zip`。先退出旧版，再打开新版；Settings → About 显示 **Notch Click Recovery 5**。原有偏好与截图目录继续使用。

- 顶部原生内容缓存现在包含 Pin 状态；固定后显示填充图标和强调色选中态，取消后恢复。附着刘海、浮动岛共用同一个按钮动作与可访问性状态。
- 取消固定后恢复正常的移出收起行为；禁用 Pin 功能也会清除固定状态。固定时进入详情页仍可取消，浮动工具栏压缩时优先保留 Pin。按 Esc 可解除固定并收起面板，既支持在刘海内输入时使用，也支持其他应用位于前台时使用；不吞掉其他应用的 Esc。
- 原生窗口按实际绘制的轮廓与可见卫星按钮判断点击范围。即使旧悬停状态未更新、宿主窗口仍保留先前的大尺寸，透明区域也放行鼠标。只允许在本面板开始的鼠标序列暂时保留捕获，抬起或检测到按键已释放后恢复；独立计时检查使用 common run-loop mode。
- 播放／暂停空格快捷键仅在悬停刘海时启用，避免固定展开后影响其他应用输入。
- Sports／Stocks 的紧凑小组件和详情页不再绘制独立不透明底板，直接透出用户选择的 Liquid Glass／白／黑面板；设置页面仍保留正常背景。

上一版 Pin and Glass 4 的输入回调错误地把 `NotchStageContainerView.stageView` 转成 `NotchStageView`；实际直接子视图是 SwiftUI 的 hosting view，因此回调一直返回 false，导致整个刘海不能点击。本版通过持有实际原生视图引用的 `NotchStageCoordinator` 查询范围，并转换窗口坐标，不再假设 hosting view 的内部层级。

验证：

```sh
bash Tools/NotchPinTests/run-click.sh
bash Tools/NotchPinTests/run.sh
bash Tools/AppAppearanceTests/run-surface.sh
bash Tools/AppAppearanceTests/run.sh
bash Tools/CommunitySportsTests/render.sh
bash Tools/CommunityFinanceTests/render.sh
bash Tools/NotchScreenFitTests/run.sh
bash Tools/SessionPrivacyTests/run-window-routes.sh
```

Pin 检查执行真实按钮动作 80 次，验证生产缓存键变化、两种布局／深浅色原生渲染的选中与取消状态，并验证 100–640 点宽度下 Pin 可达。原生输入检查使用未展示的测试面板，覆盖透明区域、其他应用开始的拖动、本窗口捕获、丢失 mouse-up、独立计时释放和禁用输入。材质检查渲染实际足球／F1／股票小组件与详情视图，用背景见证色检测是否仍有不透明底板；桌面实时折射不在离屏测试范围内。

测试没有运行完整应用、锁定系统或改变用户的屏幕配置。整机点击失灵的现场尚未复现，新增空间检查与捕获释放针对导致透明窗口挡点击的路径；仍需在实际使用中确认。

点击回归检查使用生产 NSViewRepresentable、窗口容器、控制器回调、协调器范围查询、真实形状路径和 hitTest／mouseDown／mouseUp 方法。渲染与动画服务替换为静止轮廓，在未展示的 SwiftUI hosting 层级中重现旧版错误作为反例，并检查 60 次展开点击、三种刘海形状、两种宿主大小、展开内容及透明区域。未运行完整应用或向系统注入鼠标事件。
