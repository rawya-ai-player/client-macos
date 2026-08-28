<p align="center"><img src="../assets/rawya-mark.svg" width="160" alt="若雅標誌"></p>
<h1 align="center">Rawya · 若雅</h1>
<p align="center">一款可自動產生並翻譯字幕的免費開源 macOS 播放器。</p>

<p align="center"><a href="../../README.md">English</a> · <a href="README.zh.md">简体中文</a> · <strong>繁體中文</strong> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.pt.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a></p>

<p align="center"><a href="https://rawya.app/zh-hant/">官網</a> · <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">下載最新版</a> · <a href="https://github.com/rawya-ai-player/client-macos/issues">問題回報</a></p>

## 若雅是什麼？

若雅是一款為多語言影片觀看而生的 macOS 原生播放器。它能從語音產生字幕，再翻譯成你熟悉的語言，同時保持簡單自然的播放體驗。

## 主要亮點

- 自動產生並翻譯多國語言字幕
- 字幕邊產生邊顯示，不必等待整部影片完成
- 在支援的 Mac 上使用 Apple 本機 AI，音訊不離開裝置
- 播放常見影片與音訊格式
- 支援字幕、播放清單、章節、子母畫面與播放記錄
- 可自訂影片、音訊、字幕、鍵盤、滑鼠、觸控板與手勢操作

## 系統需求

- Apple 本機 AI 字幕：macOS 26 或以上版本
- Apple 晶片基本播放：macOS 12 或以上版本
- Intel Mac 基本播放：macOS 10.15 或以上版本

## 下載

從 [GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest) 下載最新版 DMG，開啟後將若雅拖入「應用程式」資料夾。正式版本使用 Developer ID 簽署並經過 Apple 公證。

## 更新

若雅預設每天自動檢查一次穩定版更新，也可以隨時從應用程式選單選擇「檢查更新…」手動檢查。在「設定 > 一般」啟用「自動下載並安裝更新」後，通過簽章驗證的新版本會在背景下載，並在結束若雅時安裝。

自動更新與手動下載安裝使用同一個穩定版 GitHub Release。每個正式版本也包含對應的原始碼和 SHA-256 校驗檔案。

## 本機建置

1. 安裝最新版 Xcode。
2. 執行 `./other/download_libs.sh` 下載相依套件。
3. 使用 Xcode 開啟倉庫中的 `.xcodeproj`，建置主應用程式 Scheme。

## 授權

若雅採用 [GNU General Public License v3.0](../../LICENSE) 授權。第三方程式碼、函式庫與資源保留各自的聲明與授權條款。
