<p align="center"><img src="../assets/rawya-mark.svg" width="160" alt="若雅标志"></p>
<h1 align="center">Rawya · 若雅</h1>
<p align="center">一款可自动生成并翻译字幕的免费开源 macOS 播放器。</p>

<p align="center"><a href="../../README.md">English</a> · <strong>简体中文</strong> · <a href="README.zh-hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.pt.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a></p>

<p align="center"><a href="https://rawya.app/zh/">官网</a> · <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">下载最新版</a> · <a href="https://github.com/rawya-ai-player/client-macos/issues">问题反馈</a></p>

## 若雅是什么？

若雅是一款为多语言视频观看而生的 macOS 原生播放器。它能从语音生成字幕，再翻译成你熟悉的语言，同时保持简单、自然的播放体验。

## 主要亮点

- 自动生成并翻译多国语言字幕
- 字幕边生成边显示，无需等待整部视频处理完成
- 在支持的 Mac 上使用 Apple 本地 AI，音频不离开设备
- 播放常见视频和音频格式
- 支持字幕、播放列表、章节、画中画和播放历史
- 可自定义视频、音频、字幕、键盘、鼠标、触控板和手势操作

## 系统要求

- Apple 本地 AI 字幕：macOS 26 或更高版本
- Apple 芯片基础播放：macOS 12 或更高版本
- Intel Mac 基础播放：macOS 10.15 或更高版本

## 下载

从 [GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest) 下载最新版 DMG，打开后将若雅拖入“应用程序”文件夹。正式版本使用 Developer ID 签名并经过 Apple 公证。

## 更新

若雅默认每天自动检查一次稳定版更新，也可以随时通过应用菜单中的“检查更新…”手动检查。在“设置 > 通用”中启用“自动下载并安装更新”后，经过签名验证的新版本会在后台下载，并在退出若雅时安装。

自动更新与手动下载安装使用同一个稳定版 GitHub Release。GitHub 也会为每个正式版本提供源码归档。

## 本地构建

1. 安装最新版 Xcode。
2. 运行 `./other/download_libs.sh` 下载依赖。
3. 使用 Xcode 打开仓库中的 `.xcodeproj`，构建主应用 Scheme。

维护流程请参阅[版本与构建号策略](../versioning.md)、[macOS 分发指南](../macos-distribution.md)和[上游版本策略](../upstream-release-strategy.md)。

## 许可证

若雅采用 [GNU General Public License v3.0](../../LICENSE) 许可证。第三方代码、库和资源保留各自的版权声明与许可条款。
