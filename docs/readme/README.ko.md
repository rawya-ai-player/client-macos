<p align="center"><img src="../assets/rawya-mark.svg" width="160" alt="Rawya 로고"></p>
<h1 align="center">Rawya</h1>
<p align="center">자막을 자동으로 생성하고 번역하는 무료 오픈 소스 macOS 플레이어입니다.</p>

<p align="center"><a href="../../README.md">English</a> · <a href="README.zh.md">简体中文</a> · <a href="README.zh-hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <strong>한국어</strong> · <a href="README.es.md">Español</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.pt.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a></p>

<p align="center"><a href="https://rawya.app/ko/">웹사이트</a> · <a href="https://github.com/rawya-ai-player/client-macos/releases/latest">다운로드</a> · <a href="https://github.com/rawya-ai-player/client-macos/issues">문제 신고</a></p>

## Rawya란?

Rawya는 여러 언어의 영상을 보는 사용자를 위한 네이티브 macOS 플레이어입니다. 음성에서 자막을 만들고 사용자가 읽는 언어로 번역합니다.

## 주요 기능

- 여러 언어의 자막을 자동 생성 및 번역
- 전체 영상 처리를 기다리지 않고 완성된 자막부터 표시
- 지원되는 Mac에서 Apple 로컬 AI로 오디오를 기기 안에서 처리
- 일반적인 영상 및 오디오 형식 재생
- 자막, 재생 목록, 챕터, 화면 속 화면, 재생 기록 지원
- 영상, 오디오, 자막, 키보드, 마우스, 트랙패드, 제스처 설정

## 시스템 요구 사항

- Apple 로컬 AI 자막: macOS 26 이상
- Apple Silicon 기본 재생: macOS 12 이상
- Intel Mac 기본 재생: macOS 10.15 이상

## 다운로드

[GitHub Releases](https://github.com/rawya-ai-player/client-macos/releases/latest)에서 최신 DMG를 내려받아 Rawya를 응용 프로그램 폴더로 옮기세요. 안정 버전은 Developer ID로 서명되고 Apple 공증을 거칩니다.

## 업데이트

Rawya는 안정 버전 업데이트를 하루에 한 번 자동으로 확인합니다. 앱 메뉴의 “업데이트 확인…”을 선택해 언제든지 수동으로 확인할 수도 있습니다. “설정 > 일반”에서 “업데이트 자동 다운로드 및 설치”를 켜면 서명이 확인된 새 버전을 백그라운드에서 내려받고 Rawya를 종료할 때 설치합니다.

자동 업데이트와 수동 다운로드는 동일한 안정 버전 GitHub Release를 사용합니다. GitHub는 모든 정식 버전의 소스 아카이브도 제공합니다.

## 로컬 빌드

최신 Xcode를 설치하고 `./other/download_libs.sh`를 실행한 다음, Xcode에서 `.xcodeproj`를 열어 메인 앱 Scheme을 빌드합니다.

## 라이선스

Rawya는 [GNU General Public License v3.0](../../LICENSE)으로 배포됩니다. 타사 코드와 자산에는 각각의 라이선스가 적용됩니다.
