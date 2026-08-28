<p align="center"><img src="../assets/rawya-mark.svg" width="160" alt="Rawyaロゴ"></p>
<h1 align="center">Rawya</h1>
<p align="center">字幕を自動生成・翻訳する無料のオープンソースmacOSプレーヤー。</p>

<p align="center"><a href="../../README.md">English</a> · <a href="README.zh.md">简体中文</a> · <a href="README.zh-hant.md">繁體中文</a> · <strong>日本語</strong> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.pt.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a></p>

<p align="center"><a href="https://rawya.app/ja/">公式サイト</a> · <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">ダウンロード</a> · <a href="https://github.com/rawya-ai-player/client-macos/issues">問題を報告</a></p>

## Rawyaとは？

Rawyaは、さまざまな言語の動画を見る人のためのmacOSネイティブプレーヤーです。音声から字幕を生成し、読みたい言語へ翻訳します。

## 主な特長

- 多言語の字幕を自動生成・翻訳
- 動画全体の処理を待たず、完成した字幕から表示
- 対応MacではAppleのローカルAIを使用し、音声を端末内で処理
- 一般的な動画・音声形式を再生
- 字幕、プレイリスト、チャプター、ピクチャ・イン・ピクチャ、再生履歴に対応
- 映像、音声、字幕、キーボード、マウス、トラックパッド、ジェスチャーをカスタマイズ

## 動作要件

- AppleローカルAI字幕：macOS 26以降
- Appleシリコンでの基本再生：macOS 12以降
- Intel Macでの基本再生：macOS 10.15以降

## ダウンロード

[GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest)から最新のDMGをダウンロードし、Rawyaをアプリケーションフォルダへ移動してください。安定版はDeveloper IDで署名され、Appleの公証を受けています。

## アップデート

Rawyaは安定版のアップデートを1日1回自動的に確認します。アプリケーションメニューの「アップデートを確認…」から、いつでも手動で確認できます。「設定 > 一般」で「アップデートを自動的にダウンロードしてインストール」を有効にすると、署名が検証された新しいバージョンをバックグラウンドでダウンロードし、Rawyaの終了時にインストールします。

自動アップデートと手動ダウンロードは、同じ安定版GitHub Releaseを使用します。各正式リリースには、ソースアーカイブとSHA-256チェックサムファイルも含まれます。

## ローカルビルド

最新版のXcodeをインストールし、`./other/download_libs.sh`を実行してから、Xcodeで`.xcodeproj`を開いてメインアプリSchemeをビルドします。

## ライセンス

Rawyaは[GNU General Public License v3.0](../../LICENSE)で提供されます。第三者のコードや素材にはそれぞれのライセンスが適用されます。
