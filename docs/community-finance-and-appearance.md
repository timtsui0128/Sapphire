# 股票与外观

此版本交付为 `output/Sapphire Click.app`，压缩包为 `output/Sapphire-Notch-Click-Recovery-arm64.zip`。请先退出正在运行的旧版 Sapphire，再打开新版；它继续使用原有的 Sapphire 设置和截图目录，并包含[锁屏时隐藏和暂停](session-privacy.md)及[外接屏切回内置屏的窗口适配](window-fit.md)。

## Finance

打开 **Settings → Finance**。默认关注 AAPL、MSFT、NVDA；加号打开搜索，可新增代码；选中股票后可移除。关注列表和选中项目保存在本机。支持数据源能识别的美股、以 `.HK` 结尾的香港股票及以 `.L` 结尾的伦敦股票代码。

- **Show Stocks widget in the notch** 开启刘海股票小组件，点击可展开关注列表、价格和一个月的每日价格图。
- **Show selected stock as a live activity** 在刘海显示当前选中股票；可选择仅在常规交易时段显示。
- 页面显示币种、交易所、行情时间、交易状态和数据来源。伦敦 `GBp` 为便士，保留其原始单位。涨跌按上一个交易日收盘价计算，不使用一个月图表起点作为基准。
- 当前价格使用常规交易时段报价，页面明确标注。行情可能延迟；缺失数据不会显示为零，断网保留已有数据并显示缓存／错误状态，过期行情不作为刘海实时活动显示。

行情及搜索使用 Yahoo Finance 的公开端点，日收盘价备用源为 Stooq（限对应美股代码）。数据提供方可能调整公开接口。Yahoo 的[交易所与行情延迟说明](https://help.yahoo.com/kb/SLN2352.html)解释了不同市场的数据时效。此功能是 Sapphire 的独立股票面板，不同步 Apple Stocks 的账户或关注列表。

验证命令：

```sh
bash Tools/CommunityFinanceTests/run.sh
bash Tools/CommunityFinanceTests/run.sh --live
bash Tools/CommunityFinanceTests/render.sh
```

模拟网络检查覆盖日涨跌基准、缺失数据、HKD／GBp、备用源日期和非行情响应拒绝、搜索、关注列表持久化、缓存和离线行为。实际 URLSession 请求验证了默认三只美股、香港／伦敦示例及搜索。面板、紧凑小组件和空状态已通过原生离屏渲染检查。

## 跟随系统外观

在 **Settings → Appearance → App appearance** 选择 **Follow System**、**Light** 或 **Dark**。默认跟随 macOS；仅更改 Sapphire，自行观察系统切换，不更改系统外观设置。

Sports、Finance 和 Screenshots 在刘海中直接透出所选面板材质，选择 Liquid Glass 后不再额外铺黑灰色底板；独立设置预览在深色模式下使用黑色主背景，浅色模式使用系统浅色背景。选中行、缩略图和控件保留必要的层次与对比度。展开面板还可单独选择[连续的玻璃、白色或黑色表面](panel-surface.md)。

上游设置窗口及刘海内容容器固定使用深色，原来的 **Auto Light/Dark** 控制各显示器的玻璃材质，并非整个应用的主题。修复版把此选项扩展到原有设置页、展开后的音乐／日历／天气／电池／音量／计时／专注／文件工具等页面，以及引导界面、独立歌词窗口和新增的 Screenshot／Sports／Finance 面板。

浅色模式下，展开后的刘海面板及其外围留白采用浅色底，文字、输入框、分隔线、数字和进度环一起变化。展开顶栏现在与面板背景连续，不再额外画一整条黑色横条；物理摄像头缺口不能变色。收起的实时活动保留原有设置，无刘海显示器上的浮动面板采用相同的展开表面选项。唱片封面、镜像视频、壁纸预览和带色按钮中的图像／白色标识保持其原始显示。Liquid Glass 可在浅色或深色主题下使用。

设置侧栏、共用控件、原有页面及新增面板都有浅色／深色原生离屏检查；数字、三种进度视图和原生模糊视图还覆盖了同一窗口中浅色→深色→浅色切换。刘海表面检查覆盖连续顶栏、四种表面选项、浮动面板、收起状态及保持打开时切换主题。验证命令：

```sh
bash Tools/AppAppearanceTests/run.sh
bash Tools/AppAppearanceTests/check-native.sh
bash Tools/AppAppearanceTests/run-surface.sh
bash Tools/AppAppearanceTests/render-original-settings.sh
bash Tools/AppAppearanceTests/render-original-widgets.sh
```

## 蓝牙连接静音

Sapphire 的蓝牙连接／断开提示音现在默认关闭。以前保存为开启的设置会迁移一次为关闭，视觉连接提示和设备名称显示不受影响。需要声音时，可在 **Settings → Bluetooth → Play Connection Sounds** 手动开启；之后的选择会保留。此修改不更改 macOS 的全局音量或蓝牙设备自身的提示音。

```sh
bash Tools/BluetoothSoundTests/run.sh
```
