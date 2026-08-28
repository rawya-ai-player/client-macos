<p align="center">
  <img src="docs/assets/rawya-mark.svg" width="160" alt="Rawya Logo">
</p>

<h1 align="center">Rawya</h1>

<p align="center">简洁、现代的 macOS 本地音视频播放器</p>

<p align="center">
  <a href="https://rawya.app">官网</a> ·
  <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">下载最新版</a> ·
  <a href="https://github.com/rawya-ai-player/client-macos/issues">问题反馈</a>
</p>

## 简介

Rawya 专注于 macOS 本地媒体播放体验，提供清晰易用的操作界面，同时保留面向进阶用户的播放与显示设置。

## 主要功能

- 播放常见视频和音频格式
- 字幕、播放列表和章节管理
- 画中画与音乐模式
- 视频缩略图和播放历史
- 音频、视频与字幕参数调整
- 自定义键盘、鼠标、触控板和手势操作
- 支持高级播放配置与扩展能力

## 系统要求

- Intel Mac：macOS 10.15 或更高版本
- Apple 芯片 Mac：macOS 12 或更高版本

## 下载

从 [GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest) 下载最新版 DMG，打开后将 Rawya 拖入“应用程序”文件夹。正式版本使用 Developer ID 签名并经过 Apple 公证。

开发构建仅用于本地测试，不建议直接作为正式分发版本。

## 更新

Rawya 默认每天自动检查一次稳定版更新，也可以随时通过菜单中的“检查更新…”手动检查。在“设置 > 通用”中启用“自动下载并安装更新”后，经过签名验证的新版本会在后台下载，并在退出 Rawya 时安装。

自动更新与手动下载安装使用相同的稳定版 Release。每个正式版本同时提供对应源码和 SHA-256 校验文件。

## 本地构建

1. 安装最新版 Xcode。
2. 下载项目依赖：

   ```bash
   ./other/download_libs.sh
   ```

3. 使用 Xcode 打开仓库中的 `.xcodeproj` 工程。
4. 选择主应用 Scheme 和目标架构后执行构建。

Rawya 产品版本从 `1.0.0` 开始独立演进，构建号从 `1001` 全局递增；具体约定见[版本与构建号策略](docs/versioning.md)。Developer ID 签名、公证与分发流程见[macOS 分发指南](docs/macos-distribution.md)。当前 IINA 上游基线为 `v1.4.4`，后续升级约定见[上游版本策略](docs/upstream-release-strategy.md)。

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE) 许可证。项目包含的第三方代码、库和资源保留其各自的版权声明与许可条款。
