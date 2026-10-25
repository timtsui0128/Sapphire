# App language / 应用语言

Build / 构建：**Language Switch 9**

Open **Settings → General → Language → App language**. In Chinese, the same path is **设置 → 通用 → 语言 → 应用语言**.

- **Follow System / 跟随系统** is the default. A Chinese primary system language uses Simplified Chinese; other primary languages use English. Traditional Chinese system locales also use Simplified Chinese because these are the only two supported app translations.
- **English** always uses English for app UI.
- **简体中文** always uses Simplified Chinese for app UI.

Changes apply immediately, persist across launches, and do not change macOS language preferences. Switching languages does not restart Sapphire or recreate the settings/notch view state. macOS permission prompts and other system-owned dialogs may continue using the system language.

默认为**跟随系统**，也可固定选择 **English** 或**简体中文**。更改立即生效并在下次启动时保留，不修改 macOS 系统语言，不重启应用，不通过重建窗口清空正在编辑的内容。

The English/Chinese string catalog covers the settings sidebar, shared settings controls and help, app menus, screenshot shelf, Sports/F1, Stocks, and other public interface strings. Team and driver names, company names, stock symbols, song titles, filenames, notes, and other user/provider content retain their original text. Provider errors or content without an app translation fall back to their original text.

翻译覆盖设置分类、通用设置控件与说明、应用菜单、截图暂存架、体育／F1、股票等公开界面文字。球队／车手名、公司名、股票代码、歌名、文件名、笔记及其他用户或数据源内容保留原文；第三方返回的内容和错误也可能保持原语言。

## Implementation / 实现

- Preference: `SapphireAppLanguage`, with stable values `system`, `en`, and `zh-Hans`. No `AppleLanguages` override, Bundle swizzling, translated enum raw values, or changes to stored settings IDs.
- Resources: `Sapphire/Resources/Localizable.xcstrings`, English source plus Simplified Chinese. Add or edit translations here rather than replacing English strings in business logic.
- SwiftUI: locale environment updates at Settings, widget, and native notch host boundaries; dynamic UI metadata uses `LocalizedStringKey`. User/provider text stays verbatim.
- AppKit: explicit localized bundle lookup and refresh of existing app/status menus after a language change. The original menu actions and keyboard equivalents are retained.
- String symbol generation is disabled: existing English keys contain capitalization and punctuation variants and are referenced through string APIs rather than generated symbols.

## Validation / 验证

```sh
bash Tools/LocalizationTests/run.sh
bash Tools/ScreenshotShelfTests/run.sh
bash Tools/AppAppearanceTests/run-surface.sh
bash Tools/NotchPinTests/run.sh
bash Tools/NotchPinTests/run-click.sh
bash Tools/WindowFitTests/run.sh
```

The language checks use an isolated preference suite and a hidden native window. They check default/system resolution, explicit overrides, saved preferences, invalid-value fallback, resource loading, format arguments, and six language/theme scenarios in the same host. Native renders are checked with on-device Vision OCR; a SwiftUI state identity, draft text, and verbatim filename are preserved through switches. A real screenshot worker is also checked for Chinese folder-error reporting and recovery. They do not change the user's system language or exercise real lock screens, display unplugging, or third-party live data.

语言检查使用隔离偏好和隐藏原生窗口，验证默认语言、跟随系统、手动选择、持久化、无效值回退、资源与插值，以及同一宿主内的六次语言／主题切换。原生渲染通过本机 Vision 识别检查，同时验证 SwiftUI 状态、草稿与文件名保持不变。还使用真实截图工作线程验证中文文件夹错误提示及目录恢复后的正常监测。测试不会修改用户系统语言，也不实际锁屏或拔插显示器。
