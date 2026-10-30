# Sapphire · Personal Fork

**English** | [简体中文](README.zh-CN.md)

A personal macOS notch utility based on [cshariq/Sapphire](https://github.com/cshariq/Sapphire), maintained by [Ho Tim Tsui / timtsui0128](https://github.com/timtsui0128). This vibe coding project gradually improves everyday screenshot, file shelf, information card, and interface workflows.

**This is an independently maintained, unofficial fork.** The original Sapphire app, architecture, and existing features were developed by **Shariq Charolia ([@cshariq](https://github.com/cshariq)) and upstream contributors**. This fork preserves the original attribution, copyright notices, third-party credits, and **GNU AGPLv3** license.

Personal features and fixes are developed with AI assistance. This is not an official Sapphire release and is not affiliated with Apple Sports or Apple Stocks.

- Upstream project: [cshariq/Sapphire](https://github.com/cshariq/Sapphire)
- Original upstream introduction: [docs/upstream-README.md](docs/upstream-README.md)
- Third-party credits and licenses: [CREDITS.md](CREDITS.md)
- Full license: [LICENSE](LICENSE)

## Features and changes

These personal changes are relative to upstream commit [`2e8085676209cbbb424bc60fd7ea2f11bfd625aa`](https://github.com/cshariq/Sapphire/commit/2e8085676209cbbb424bc60fd7ea2f11bfd625aa), documented on **2026-10-30**. This README is available in English and Chinese; most detailed module notes are in Chinese.

| Feature | Behavior in this fork | Details |
| --- | --- | --- |
| Screenshot shelf | Collect system screenshots and drag multiple selected images together; choose immediate collection or keep the system floating preview; new captures take priority on the next notch click; history does not trigger a persistent capsule | [Screenshot workflow](docs/screenshot-shelf.md) |
| Screenshot storage | Move automatically collected screenshots into Sapphire's dedicated folder; choose manual removal, cleanup after 24 hours, or cleanup after a successful drag; manual import is also supported | [Storage and retention](docs/screenshot-shelf.md#保存与收集范围) |
| Quick AirDrop | AirDrop tab inside File Shelf, beside Screenshots and Files; drop items, choose files or clipboard content, and share multiple screenshots together | [Quick AirDrop](docs/quick-airdrop.md) |
| Football and F1 | Football schedules, scores, and followed teams; F1 calendar, results, positions, lap counts, followed drivers/constructors, and notch activity cards | [Sports / F1](docs/community-sports.md) |
| Stock watchlist | AAPL, MSFT, and NVDA by default, with search, add/remove controls, quotes, historical charts, and notch widgets | [Stocks / Finance](docs/community-finance-and-appearance.md) |
| In-app updates | Signed GitHub update channel with optional background preparation, byte/speed progress, and incremental updates from compatible builds | [App updates](docs/app-updates.md) |
| App language | Follow System (default), English, or Simplified Chinese; changes apply immediately and persist across launches | [Language settings](docs/app-language.md) |
| Appearance and glass | Follow the system or choose light/dark mode; expanded top bar and panel support Match Panel, Liquid Glass, White, and Black; Sports/Stocks show the panel material underneath | [Panel materials](docs/panel-surface.md) |
| Silent Bluetooth alerts | Sapphire's Bluetooth connect/disconnect sounds are off by default, with a settings toggle | [Bluetooth sounds](docs/community-finance-and-appearance.md#蓝牙连接静音) |
| Lock screen privacy | Hide the interface, prevent reopening, and pause screenshot/clipboard collection when locked or switching user sessions; do not collect missed locked-session content after unlocking | [Session privacy](docs/session-privacy.md) |
| Display switching | Keep the settings window and expanded notch within the available screen after switching displays; scroll overflowing content | [Window and notch sizing](docs/window-fit.md) |
| External display line | Click the line from the screen's top edge; retain the original curved transition when expanded; match Liquid Glass tone to the wallpaper or choose light/dark glass | [External display appearance](docs/external-display-bar.md) |
| Pin and click fixes | Highlight the pinned state, allow unpinning from detail views, and use Esc to unpin and collapse; fix click-region lookup through the SwiftUI hosting hierarchy | [Pin and input](docs/pin-and-input.md) |
| Music artwork synchronization | Clear the previous song's cover when new metadata arrives first; accept delayed cover updates and reject stale image downloads | [Artwork fix](docs/releases/0.1.4.md) |
| Security and glass readability | Keychain music credentials, password/OAuth protection, and frosted panels with controls below the system menu bar | [Security notes](docs/security-hardening.md) · [0.1.5 changes](docs/releases/0.1.5.md) |
| Window snapping | Preserve the dragged window, verify and retry placement, match the destination display, and explain permission/layout failures | [0.1.6 changes](docs/releases/0.1.6.md) |

Open **File Shelf → Screenshots** for screenshots, and use its gear menu to change retention. Configure Sports, Finance, and Appearance in their respective settings pages.

## Current version and supported scope

- The current source build is labeled **Window Snapping 16** (version **0.1.6**, build **16**). A complete local app build and signature verification have been completed.
- Personal development takes place on **`codex/personal-notched-tools`**. `main` retains the upstream state from the fork; this branch is based on the commit above and has not merged the later upstream macOS 27 charging-limit changes.
- The minimum deployment target is macOS 14. Complete builds and local packages have been verified on Apple Silicon (arm64); Intel hardware and other macOS versions have not been fully validated.
- Upstream paid modules whose source is not public continue to use public placeholders or compatibility implementations. The independently implemented Sports/Finance features do not require those private modules and do not connect or sync with Apple Sports/Stocks accounts.
- This is a personal experimental project. Regression checks are included, but they do not cover every device, permission state, or interaction. Implementation and validation notes are in `docs/`.

## Download and updates

Download the Apple Silicon app from [Personal Releases](https://github.com/timtsui0128/Sapphire/releases). Install the first update-enabled version once, then use **Settings → About → Updates**. Releases include a signed feed, signed app archive, checksums, and the exact source commit. See [update and release instructions](docs/app-updates.md).

## Build from source

Requirements: macOS, Python 3, a full Xcode installation, and network access to download the pinned Swift Package dependencies. The public-source build workflow has been verified with **Xcode 27.1**.

```sh
git clone --branch codex/personal-notched-tools https://github.com/timtsui0128/Sapphire.git
cd Sapphire
bash Tools/build-sapphire-public.sh
```

Build output:

```text
output/public-build/Build/Products/Debug/Sapphire.app
```

The script generates an isolated Xcode project in `output/` for the current toolchain, preserves the original project, uses the repository's dependency lockfile, and ad-hoc signs and verifies the local build. Build output, caches, and local configuration are excluded from Git.

Local ad-hoc signing is not Developer ID signing or Apple notarization; privileged services that require developer signing may be unavailable. Screenshot collection only needs access to the screenshot save folder and does not request screen recording permission. Other app features request their own system permissions as needed.

Quit any upstream or older Sapphire instance before opening this build. The fork currently uses the upstream Bundle ID and settings/data directories, so keep backups of data you need. Version 0.1.0 introduced a signed update channel for this fork; configure it under Settings → About → Updates. Install an update-enabled version once, then update inside the app. Automatic preparation is a separate opt-in and may install a prepared update when you next quit. The inherited upstream `Sapphire.pkg` is also not a build of this fork.

## Checks and validation

Run these checks in a normal macOS user session. Most use temporary files, simulated networking, and hidden native windows; some clipboard or drag-and-drop checks need a graphical user session.

```sh
bash Tools/QuickAirDropTests/run.sh
bash Tools/ScreenshotShelfTests/run.sh
bash Tools/MusicArtworkTests/run.sh
bash Tools/SecurityRegressionTests/run.sh
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

Checks cover multi-screenshot drag-and-drop, retention, simulated market data, theme rendering, session privacy, display sizing, 80 Pin actions, and 80 native mouse-down/up callbacks through the SwiftUI hosting hierarchy. Each local delivery also receives a complete build and signature verification.

Offscreen checks use real controls or production methods, but do not replace everyday use of the full app. Privacy checks did not actually lock the user's computer, glass image checks do not simulate real-time desktop refraction, and F1 has not been fully validated during a live race. Module notes describe the specific coverage and limits.

## Data sources and known limitations

- Football and F1 positions use ESPN public endpoints; F1 schedules and historical results use Jolpica F1. Availability and update speed depend on the providers. Missing data is not fabricated, and cached/stale states are shown explicitly.
- Stocks use Yahoo Finance public endpoints, with Stooq as a daily closing-price fallback for some US equities. Quotes may be delayed and public endpoints may change. This is not a trading tool.
- Screenshots are collected after macOS actually saves the image as a file. Automatic collection moves the original into the app's dedicated folder; manual import copies it. Control-key screenshots sent only to the clipboard are not collected automatically.
- This fork does not currently provide a general third-party plugin SDK or marketplace. New features are integrated as source modules. Reused projects will have their licenses checked individually, with the corresponding attribution and notices preserved.

## Attribution and license

**Original Sapphire:** Shariq Charolia ([@cshariq](https://github.com/cshariq)) and upstream contributors. The original Git history, source-file author/copyright notices, and [CREDITS.md](CREDITS.md) are preserved.

**Personal fork and modifications:** Ho Tim Tsui ([@timtsui0128](https://github.com/timtsui0128)), 2026, with AI-assisted development. Personal changes are documented here and in the module notes. This fork does not imply support or endorsement by the original author.

This fork continues under the **GNU Affero General Public License, Version 3 (AGPLv3)**; see [LICENSE](LICENSE) for the full terms. No additional personal-use-only or noncommercial restrictions are added. Existing third-party components retain their respective copyright and license notices.

When redistributing builds, preserve the required notices and provide the corresponding complete source and build scripts as required by the license. Any binary Release should identify its exact source tag or commit.
