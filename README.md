<p align="center">
  <img src="docs/assets/rawya-mark.svg" width="160" alt="Rawya logo">
</p>

<h1 align="center">Rawya</h1>

<p align="center">A free, open source macOS player that automatically generates and translates subtitles.</p>

<p align="center">
  <strong>English</strong> ·
  <a href="docs/readme/README.zh.md">简体中文</a> ·
  <a href="docs/readme/README.zh-hant.md">繁體中文</a> ·
  <a href="docs/readme/README.ja.md">日本語</a> ·
  <a href="docs/readme/README.ko.md">한국어</a> ·
  <a href="docs/readme/README.es.md">Español</a> ·
  <a href="docs/readme/README.fr.md">Français</a> ·
  <a href="docs/readme/README.de.md">Deutsch</a> ·
  <a href="docs/readme/README.pt.md">Português</a> ·
  <a href="docs/readme/README.ru.md">Русский</a> ·
  <a href="docs/readme/README.ar.md">العربية</a>
</p>

<p align="center">
  <a href="https://rawya.app">Website</a> ·
  <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">Download</a> ·
  <a href="https://github.com/rawya-ai-player/client-macos/issues">Issues</a>
</p>

## What is Rawya?

Rawya is a native macOS media player for people who watch videos in different languages. It can generate subtitles from speech and translate them into the language you read, while keeping the playback experience simple.

## Highlights

- Automatically generate and translate subtitles in multiple languages
- Show completed subtitles while the rest of the video is still being processed
- Process audio locally with Apple AI on supported Macs
- Play common video and audio formats
- Manage subtitles, playlists, chapters, picture-in-picture, and playback history
- Customize video, audio, subtitle, keyboard, mouse, trackpad, and gesture controls

## Requirements

- Apple local AI subtitles: macOS 26 or later
- Basic playback on Apple silicon: macOS 12 or later
- Basic playback on Intel Mac: macOS 10.15 or later

## Download

Download the latest DMG from [GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest), open it, and drag Rawya into Applications. Stable builds are signed with Developer ID and notarized by Apple.

## Updates

Rawya checks for stable updates automatically once a day. You can also choose **Check for Updates…** from the application menu at any time. Enable **Automatically download and install updates** in **Settings > General** to download verified updates in the background and install them when Rawya quits.

Automatic updates and manual downloads use the same stable GitHub Release. Every stable release also includes its source archive and SHA-256 checksum files.

## Build locally

1. Install the latest Xcode.
2. Download dependencies with `./other/download_libs.sh`.
3. Open the repository's `.xcodeproj` in Xcode and build the main app scheme.

See the [versioning strategy](docs/versioning.md), [macOS distribution guide](docs/macos-distribution.md), and [upstream release strategy](docs/upstream-release-strategy.md) for maintainer workflows.

## License

Rawya is licensed under the [GNU General Public License v3.0](LICENSE). Third-party code, libraries, and assets retain their respective notices and licenses.
