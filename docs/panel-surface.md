# 展开顶栏与面板材质

当前交付为 `output/Sapphire Blend.app`，压缩包为 `output/Sapphire-Adaptive-Glass-and-Capture-arm64.zip`。先退出旧版，再打开新版；**Settings → About** 显示 **Adaptive Glass and Capture 8**。

打开 **Settings → Appearance → App appearance → Top bar & panel**：

- **Match Panel**：默认选项。顶栏与面板使用连续背景，去掉之前软件绘制的黑色横条，遵循下方 Expanded Notch Appearance 的材质设置。
- **Liquid Glass**：展开顶栏与内容使用一块连续的系统玻璃，不叠加不透明的黑色条。旧系统使用原生模糊材质；开启“降低透明度”时回退为符合当前主题的实色。
- **White**：整个展开面板及顶栏使用白色背景与深色文字。
- **Black**：整个展开面板及顶栏使用黑色背景与浅色文字。

选择立即生效并保存在本机，不用重新打开面板。白色／黑色选项独立于 Settings 窗口的 App appearance；截图、Sports、Finance 等嵌套内容会继承面板主题，返回按钮、设置／文件按钮、电池和连接状态图标一起调整对比度。Match Panel 尊重每块显示器选择的玻璃明暗样式。

Sports／Stocks 的紧凑小组件和详情页现在直接透出所选材质，移除内部不透明底板；独立 Settings 预览仍保留正常画布。

此选项调整软件绘制的展开表面。物理摄像头缺口本身不能变色。内置屏的收起状态及实时活动沿用原有材质；外接屏可使用新的[细条与半透明活动材质](external-display-bar.md)。屏幕适配、锁屏隐藏与截图收集逻辑保留。

验证：

```sh
bash Tools/AppAppearanceTests/run.sh
bash Tools/AppAppearanceTests/run-surface.sh
bash Tools/NotchScreenFitTests/run.sh
```

测试涵盖偏好保存、无效旧值回退、显式白／黑色与每显示器玻璃主题、玻璃及旧系统回退、降低透明度、已挂载面板即时切换、嵌套内容主题继承，以及八种主题／表面组合的真实按钮与电池原生离屏渲染。深浅色设置控件和对比度验证图位于 `output/appearance-renders/`。玻璃后台选择通过生产解析器检查；离屏图片用于文字和控件对比度，不模拟桌面背后的实时折射。
