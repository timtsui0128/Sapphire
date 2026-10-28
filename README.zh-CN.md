# Sapphire · 个人分支

[English](README.md) | **简体中文**

一个基于 [cshariq/Sapphire](https://github.com/cshariq/Sapphire) 的个人 macOS 刘海工具实验项目，由 [Ho Tim Tsui / timtsui0128](https://github.com/timtsui0128) 维护。通过 vibe coding 逐步改进自己每天使用的截图、文件暂存、信息卡片和界面体验。

**这是独立维护的非官方分支。** Sapphire 的原始应用、基础架构及原有功能由 **Shariq Charolia（[@cshariq](https://github.com/cshariq)）与上游贡献者**开发。本分支保留原作者署名、原有版权声明、第三方致谢和 **GNU AGPLv3** 许可证。

This is an unofficial personal fork of Sapphire, originally created by Shariq Charolia and upstream contributors. It adds personal workflow features and fixes with AI-assisted development. It is not an official Sapphire release and is not affiliated with Apple Sports or Apple Stocks.

- 上游项目：[cshariq/Sapphire](https://github.com/cshariq/Sapphire)
- 上游原始介绍：[docs/upstream-README.md](docs/upstream-README.md)
- 第三方致谢与许可：[CREDITS.md](CREDITS.md)
- 完整许可证：[LICENSE](LICENSE)

## 本分支增加与修改了什么

以下是相对于上游提交 [`2e8085676209cbbb424bc60fd7ea2f11bfd625aa`](https://github.com/cshariq/Sapphire/commit/2e8085676209cbbb424bc60fd7ea2f11bfd625aa) 的个人修改，记录日期为 **2026-10-28**。

| 功能 | 本分支的行为 | 使用说明 |
| --- | --- | --- |
| 截图暂存架 | 收集系统截图，多选后一次拖出多张；可选立即收集或保留系统浮动预览；截图历史不触发常驻胶囊 | [截图与文件保存](docs/screenshot-shelf.md) |
| 截图保存策略 | 自动收集后移入 Sapphire 专用目录；可选手动移除、24 小时清理、成功拖出后清理；支持手动导入 | [保存策略与限制](docs/screenshot-shelf.md#保存与收集范围) |
| 快速隔空投送 | 文件架内独立 AirDrop 标签，与截图／文件并列；拖入内容、选择文件、分享剪贴板或多张截图一起 AirDrop | [隔空投送入口](docs/quick-airdrop.md) |
| 足球与 F1 | 足球赛程、比分和关注球队；F1 赛历、赛后结果、排名、圈数、关注车手／车队和刘海状态卡 | [Sports / F1](docs/community-sports.md) |
| 股票关注列表 | 默认关注 AAPL、MSFT、NVDA，支持搜索增删、报价、历史图表和刘海小组件 | [Stocks / Finance](docs/community-finance-and-appearance.md) |
| 应用内更新 | 签名 GitHub 更新渠道，支持后台准备、下载大小／速度显示及兼容版本间的增量更新 | [更新与发布](docs/app-updates.md) |
| 界面语言 | 默认跟随系统，可选择 English 或简体中文；切换立即生效并在下次启动时保留 | [语言设置](docs/app-language.md) |
| 主题与玻璃材质 | 应用可跟随系统或选择浅色／深色；展开顶栏和面板支持 Match Panel、Liquid Glass、White、Black；Sports／Stocks 透出面板材质 | [面板材质](docs/panel-surface.md) |
| 蓝牙提示静音 | 默认关闭 Sapphire 的蓝牙连接／断开提示音，并提供设置开关 | [蓝牙声音](docs/community-finance-and-appearance.md#蓝牙连接静音) |
| 锁屏隐私 | 锁屏和用户会话切换时隐藏界面、阻止重新弹窗并暂停截图／剪贴板收集；解锁后不补收锁屏期间内容 | [锁屏行为](docs/session-privacy.md) |
| 内外接屏适配 | 切换显示器后约束设置窗口和展开刘海尺寸，支持内容溢出滚动 | [窗口与刘海适配](docs/window-fit.md) |
| 外接屏细条 | 顶部细条支持顶边点击；展开时保留原版弧形过渡，Liquid Glass 可匹配壁纸明暗或指定浅色／深色 | [外接屏样式](docs/external-display-bar.md) |
| Pin 与点击修复 | 固定后图标点亮，详情页可取消，Esc 可解除固定并收起；修正 SwiftUI hosting 层级下的点击范围查询 | [Pin 与输入](docs/pin-and-input.md) |

截图主入口为 **File Shelf → Screenshots**，保存策略可通过截图页齿轮调整。Sports、Finance 和 Appearance 分别在对应设置页中配置。

## 当前源码版本与运行范围

- 当前源码的构建标记为 **Shelf AirDrop 12**（版本 **0.1.2**，构建 **12**），已在本机完成完整应用构建和签名复检。
- 个人开发分支为 **`codex/personal-notched-tools`**。`main` 保留 Fork 时的上游状态；本分支基于上面标注的提交，尚未合并上游后续的 macOS 27 充电限制改动。
- 最低部署目标为 macOS 14；当前完整构建与本地安装包在 Apple Silicon（arm64）Mac 上验证。Intel 机器和不同 macOS 版本尚未完整验收。
- 上游未公开的付费模块继续使用公开占位或兼容实现。独立实现的 Sports／Finance 不依赖这些私有模块，也不连接或同步 Apple Sports／Stocks 账户。
- 当前是个人实验项目。已加入回归检查，但未覆盖所有设备、权限状态和实际操作场景；修改和验证过程记录在 `docs/`。

## 下载与更新

在[个人版发布页](https://github.com/timtsui0128/Sapphire/releases)下载 Apple Silicon 应用。首次安装一次后，今后在“设置 → 关于 → 更新”操作。每次发布包含签名更新列表、签名安装包、校验和及对应源码提交。详见[更新与发布说明](docs/app-updates.md)。

## 从源码构建

需要 macOS、Python 3、完整 Xcode 和可下载锁定 Swift Package 依赖的网络环境。本分支的公开源码构建流程已在 **Xcode 26.3** 验证。

```sh
git clone --branch codex/personal-notched-tools https://github.com/timtsui0128/Sapphire.git
cd Sapphire
bash Tools/build-sapphire-public.sh
```

构建产物：

```text
output/public-build/Build/Products/Debug/Sapphire.app
```

脚本在 `output/` 中生成兼容当前工具链的隔离 Xcode 工程，保留原始工程，使用仓库中的依赖锁定文件，最后对本机构建做 ad-hoc 签名及签名校验。`output/`、编译缓存和本机配置不提交到 Git。

本地 ad-hoc 签名不等同于 Developer ID 签名或 Apple 公证；要求开发者签名的特权服务可能不可用。截图收集本身只需要访问截图保存文件夹，不申请屏幕录制权限。应用其他功能按需使用各自的系统权限。

如果同时装有上游或旧版 Sapphire，先退出再启动本分支构建。当前仍使用上游 Bundle ID 和设置／数据目录，请保留需要的数据。0.1.0 版起使用本分支自己的签名更新渠道，在“设置 → 关于 → 更新”中配置。首次需要安装一次带更新器的版本，之后可以在应用内更新。后台准备更新需要单独开启；准备好的更新可在下次退出时安装。仓库中继承的上游 `Sapphire.pkg` 也不是本分支的构建产物。

## 检查与验证

在正常的 macOS 用户会话中运行。多数检查使用临时文件、模拟网络和未展示的原生窗口；少数剪贴板或拖放检查需要图形用户会话。

```sh
bash Tools/QuickAirDropTests/run.sh
bash Tools/ScreenshotShelfTests/run.sh
bash Tools/CommunitySportsTests/run.sh
bash Tools/F1LiveTests/run.sh
bash Tools/CommunityFinanceTests/run.sh
bash Tools/LocalizationTests/run.sh
python3 Tools/UpdateTests/run.py
bash Tools/AppAppearanceTests/run.sh
bash Tools/AppAppearanceTests/run-surface.sh
bash Tools/BluetoothSoundTests/run.sh
bash Tools/SessionPrivacyTests/run.sh
bash Tools/SessionPrivacyTests/run-window-routes.sh
bash Tools/ClipboardPrivacyTests/run.sh
bash Tools/WindowFitTests/run.sh
bash Tools/NotchScreenFitTests/run.sh
bash Tools/NotchPinTests/run.sh
bash Tools/NotchPinTests/run-click.sh
```

专项检查包括多截图拖放、保存策略、模拟行情、主题渲染、会话隐私、屏幕适配、80 次 Pin 动作，以及 SwiftUI hosting 层级中的 80 次原生鼠标按下／抬起回调检查。每次本地交付另做完整构建和签名复检。

离屏检查使用了真实控件或生产方法，但不能替代完整 App 的日常运行验收。锁屏检查没有实际锁定用户电脑，玻璃图片检查不模拟桌面实时折射；F1 也尚未在真实比赛过程中完整操作验收。各模块文档说明了具体覆盖范围。

## 数据来源与已知限制

- 足球／F1 排名使用 ESPN 的公开数据端点，F1 赛历与历史结果使用 Jolpica F1。接口与更新速度由数据提供方决定，缺失数据不补造，缓存和过期状态会明确显示。
- 股票使用 Yahoo Finance 公开端点，部分美股的日收盘价使用 Stooq 备用源。报价可能延迟，公开接口可能发生变化；这不是交易工具。
- 截图在 macOS 将图片实际保存为文件之后收集。自动收集会移动原文件到应用专用目录；手动导入会复制原文件。按住 Control 的仅剪贴板截图目前不自动收集。
- 本分支当前没有通用第三方插件 SDK，也没有插件市场；新增功能以源码模块方式集成。后续复用其他项目时会逐项核对许可证，并保留相应署名与声明。

## 署名与许可证

**Original Sapphire:** Shariq Charolia（[@cshariq](https://github.com/cshariq)）与上游贡献者。原项目的 Git 历史、源文件中的作者／版权信息和 [CREDITS.md](CREDITS.md) 均予以保留。

**Personal fork and modifications:** Ho Tim Tsui（[@timtsui0128](https://github.com/timtsui0128)），2026；使用 AI 辅助开发，个人修改记录见本文及模块文档。此分支不代表原作者提供支持或认可这些改动。

本分支继续采用 **GNU Affero General Public License, Version 3（AGPLv3）**，完整条款见 [LICENSE](LICENSE)。本分支没有新增“仅限个人使用”或“禁止商用”的许可证限制。已有第三方组件仍保留其各自的版权和许可声明。

重新分发本分支构建时，请按许可证要求保留相关声明并提供与该构建对应的完整源码及构建脚本。若发布二进制 Release，应同时关联确切源码 tag 或 commit。
