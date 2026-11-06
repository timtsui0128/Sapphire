# 展开顶栏与面板材质

使用个人分支的最新版本，版本信息位于 **Settings → About**。从支持应用内更新的版本可在此检查更新。

打开 **Settings → Appearance → App appearance → Top bar & panel**：

- **Liquid Glass**：默认选项。展开顶栏和内容共用一层清透的原生玻璃，透出壁纸或下方窗口的颜色和轮廓，配合薄色罩和细高光边。旧系统使用原生窗口背后模糊。
- **Light Glass／Dark Glass**：替代原来的 White／Black，保留对应的明暗文字与色调，但背景可以透出。开启系统“降低透明度”或“增强对比度”时，这些玻璃选项回退为当前主题的实色。
- **Match Panel**：顶栏与内容遵循下方 Expanded Notch Appearance 的设置，可保留原来的实色风格。

选择立即生效并保存在本机，不用重新打开面板。浅色／深色玻璃独立于 Settings 窗口的 App appearance；截图、Sports、Finance 等嵌套内容会继承面板主题，返回按钮、设置／文件按钮、电池和连接状态图标一起调整对比度。Match Panel 尊重每块显示器选择的玻璃明暗样式。

0.1.5 起，贴顶半透明面板的工具按钮位于系统菜单栏下方，并按当前显示器的菜单栏高度留白。内容区同步下移并保持屏幕高度限制，避免和苹果菜单、应用菜单、时间图标重叠；胶囊原有底部工具栏及展开轮廓保持不变。

Sports／Stocks 的紧凑小组件和详情页现在直接透出所选材质，移除内部不透明底板；独立 Settings 预览仍保留正常画布。

此选项调整软件绘制的展开表面。物理摄像头缺口本身不能变色。内置屏的收起状态及实时活动沿用原有材质；外接屏可使用新的[细条与半透明活动材质](external-display-bar.md)。屏幕适配、锁屏隐藏与截图收集逻辑保留。

验证：

```sh
bash Tools/AppAppearanceTests/run.sh
bash Tools/AppAppearanceTests/run-surface.sh
bash Tools/AppAppearanceTests/check-native.sh
bash Tools/NotchScreenFitTests/run.sh
```

测试涵盖偏好保存、无效旧值回退、深浅玻璃与每显示器主题、原生 Clear Glass、旧系统回退、降低透明度、已挂载面板即时切换、嵌套内容主题继承，以及八种主题／表面组合的真实按钮与电池原生离屏渲染。离屏图片用于文字和控件对比度，实际桌面玻璃随窗口与壁纸变化。
