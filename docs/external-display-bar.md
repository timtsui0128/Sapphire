# 外接屏顶部细条

本地构建：**Language Switch 9**，产物 `output/Sapphire Bilingual.app`，压缩包 `output/Sapphire-Bilingual-English-Chinese-arm64.zip`。先退出正在运行的 Sapphire，再打开新版。

入口：**Settings → Appearance → App appearance → External display**。

- **Menu Bar Line**（默认）：通过 Core Graphics 检测外接屏；只在没有物理刘海的外接屏上启用。闲置时显示最多 80 × 4 pt 的细条，透出后面的菜单栏。内置屏保持原有样式。
- **Original**：恢复原来的每显示器刘海／Floating Island 配置，不覆盖那些已保存的设置。
- **External glass tone → Match Wallpaper**：从每块显示器的静态壁纸可见顶部区域估计明暗，外接屏细条与展开的 Liquid Glass 面板一起调整；与应用内部深色模式独立。采样考虑每块显示器宽高比的居中填充裁切，不需要屏幕录制权限。
- 系统菜单栏可能还受动态壁纸、桌面空间和透明混合影响，无法保证逐像素匹配。可选择 **Light Glass** 或 **Dark Glass**；菜单栏浅色时优先选择 Light Glass。展开面板需在 **Top bar & panel** 选择 **Liquid Glass**；显式 White／Black 仍尊重原选择。
- 细条在原有菜单栏高度内居中，按显示器比例对齐像素，无原黑胶囊底板、阴影或光晕。点击范围左右各延伸 6 pt，并从细条一直延伸到屏幕顶边，覆盖原生视图可能存在的顶部间距；邻近菜单项仍接收自己的点击。
- 展开时使用原版贴顶刘海轮廓，恢复两侧向内收拢的顶部弧形过渡和原版工具栏，不再跟随浮动胶囊的圆角矩形轮廓。
- 原有悬停、点击展开和文件拖入行为继续使用原来的入口与隐私保护。细条只用于闲置状态；有实时内容时保留可读的正常高度，改用深色原生玻璃／模糊材质。
- 截图历史不再计入原有的常驻文件架活动；收集截图后不会仅因截图还在暂存架里，就重新出现常驻胶囊或挤占音乐的优先级。普通文件架活动仍按原设置工作。
- 展开后的面板仍使用 **Top bar & panel** 的选择。macOS 15 使用 NSVisualEffectView 模糊，支持的更新系统使用原生玻璃；减少透明度开启时使用不透明背景。
- 应用主题不改动 macOS 的全局主题、壁纸或辅助功能设置。

macOS 菜单栏本身带有透明效果，深色模式不保证背景为纯黑。若要减少壁纸颜色的影响，可自行使用 **系统设置 → 辅助功能 → 显示 → 减少透明度**；这会影响整个系统的透明界面。参见 [Apple 的显示颜色说明](https://support.apple.com/en-gb/guide/mac-help/mchl11ddd4b3/15.0/mac/15.0)。单张照片不足以确认菜单栏偏白的全部原因。

验证：

```sh
bash Tools/NotchPinTests/run-click.sh
bash Tools/AppAppearanceTests/run-surface.sh
bash Tools/NotchScreenFitTests/run.sh
```

点击检查涵盖硬件刘海、悬浮岛、无刘海和外接细条，两种原生宿主尺寸共 80 次鼠标按下／抬起回调。外接细条检查包括实际原生窗口顶边、距顶 0.5／4 pt、细条与边距点击，在 8 pt 的视图顶部间距下验证完整点击通路；另检查邻近菜单项穿透、原版顶部弧线、展开后的输入和视图重挂载。外观检查覆盖自动检测策略、设置持久化、系统主题与面板主题独立、macOS 15 原生模糊与减少透明度回退。

这些检查使用隐藏窗口和测试数据；不自动拔插用户的显示器，也不切换用户的全局系统外观。
