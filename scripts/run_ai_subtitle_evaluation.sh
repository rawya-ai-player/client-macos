#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rawya-ai-subtitle-evaluation.XXXXXX")"
BINARY="$BUILD_ROOT/ai-subtitle-eval"

cleanup() {
  if [[ -d "$BUILD_ROOT" ]]; then
    /usr/bin/trash "$BUILD_ROOT"
  fi
}
trap cleanup EXIT

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcrun --sdk macosx swiftc \
  -parse-as-library \
  "$ROOT/Tests/AISubtitleEvaluation/Support.swift" \
  "$ROOT/iina/AISubtitleCore.swift" \
  "$ROOT/iina/AISubtitleFile.swift" \
  "$ROOT/iina/AISubtitleAudioExtractor.swift" \
  "$ROOT/iina/AISubtitleScheduler.swift" \
  "$ROOT/iina/AISubtitleCloudProvider.swift" \
  "$ROOT/iina/AISubtitleAliyunProvider.swift" \
  "$ROOT/iina/WhisperCppAISubtitleProvider.swift" \
  "$ROOT/iina/AppleAISubtitleProvider.swift" \
  "$ROOT/Tests/AISubtitleEvaluation/DictationTranscriber.swift" \
  "$ROOT/Tests/AISubtitleEvaluation/main.swift" \
  -o "$BINARY"

"$BINARY" "$@"
