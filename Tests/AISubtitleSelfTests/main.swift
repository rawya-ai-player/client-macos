import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  guard condition() else {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}

func expectEventually(timeout: TimeInterval = 2,
                      _ condition: () -> Bool,
                      _ message: String) {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return }
    Thread.sleep(forTimeInterval: 0.01)
  }
  expect(condition(), message)
}

func waitWhileRunningMainLoop(_ semaphore: DispatchSemaphore,
                              timeout: TimeInterval) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if semaphore.wait(timeout: .now()) == .success { return true }
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
  }
  return semaphore.wait(timeout: .now()) == .success
}

let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
  .appendingPathComponent("ai-subtitle-tests-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: tempRoot) }

let english = AISubtitleLanguage("en")
let chinese = AISubtitleLanguage("zh-Hans")
expect(AISubtitleLanguageCatalog.sourceLanguages.first?.code == nil
       && AISubtitleLanguageCatalog.sourceLanguages.first?.fallbackTitle == "Choose Language"
       && !AISubtitleLanguageCatalog.targetLanguages.contains(where: { $0.code == nil }),
       "Spoken-language selection should use a prompt instead of advertising automatic detection")
expect(english.isEquivalent(to: AISubtitleLanguage("en-US")) &&
       chinese.isEquivalent(to: AISubtitleLanguage("zh-CN")) &&
       !chinese.isEquivalent(to: AISubtitleLanguage("zh-Hant")),
       "Language matching should ignore regions while preserving Chinese script conversion")
let textNormalizer = AISubtitleTargetTextNormalizer()
expect(textNormalizer.normalize("那會造成損害的", language: chinese) == "那会造成损害的"
       && textNormalizer.normalize("那会造成损害的", language: AISubtitleLanguage("zh-Hant")) == "那會造成損害的"
       && textNormalizer.normalize("It stays unchanged", language: english) == "It stays unchanged",
       "Chinese translation output should match the selected script without changing other languages")
let media = AISubtitleMediaContext(url: URL(fileURLWithPath: "/tmp/movie.mp4"),
                                   isNetworkResource: false,
                                   fileSize: 123,
                                   fileModifiedAt: Date(timeIntervalSince1970: 100),
                                   audioTrackID: 1,
                                   sourceLanguage: english,
                                   targetLanguage: chinese)
let request = AISubtitleProviderRequest(sourceLanguage: english,
                                        targetLanguage: chinese,
                                        media: media)
let suggestionMediaURL = URL(fileURLWithPath: "/tmp/suggestion.mov")
expect(AISubtitleSuggestionPolicy.shouldSchedule(isEnabled: true,
                                                 mediaURL: suggestionMediaURL,
                                                 previouslySuggestedMediaURL: nil),
       "A subtitle suggestion should be scheduled once for eligible media")
expect(!AISubtitleSuggestionPolicy.shouldSchedule(isEnabled: false,
                                                  mediaURL: suggestionMediaURL,
                                                  previouslySuggestedMediaURL: nil)
       && !AISubtitleSuggestionPolicy.shouldSchedule(isEnabled: true,
                                                     mediaURL: suggestionMediaURL,
                                                     previouslySuggestedMediaURL: suggestionMediaURL),
       "Disabled or previously shown subtitle suggestions should not be rescheduled")
expect(AISubtitleSuggestionPolicy.shouldPresent(scheduledMediaURL: suggestionMediaURL,
                                                currentMediaURL: suggestionMediaURL,
                                                isPlaybackActive: true,
                                                hasAudioTracks: true,
                                                hasSubtitleTracks: false,
                                                hasExportableAISubtitles: false),
       "Active media with audio and no subtitles should offer AI subtitle generation")
expect(!AISubtitleSuggestionPolicy.shouldPresent(scheduledMediaURL: suggestionMediaURL,
                                                 currentMediaURL: suggestionMediaURL,
                                                 isPlaybackActive: true,
                                                 hasAudioTracks: true,
                                                 hasSubtitleTracks: true,
                                                 hasExportableAISubtitles: false),
       "Media with an existing subtitle track should not show the AI subtitle suggestion")
expect(!AISubtitleSuggestionPolicy.shouldPresent(scheduledMediaURL: suggestionMediaURL,
                                                 currentMediaURL: suggestionMediaURL,
                                                 isPlaybackActive: true,
                                                 hasAudioTracks: true,
                                                 hasSubtitleTracks: false,
                                                 hasExportableAISubtitles: true),
       "Media with reusable AI subtitle cache should not show a duplicate suggestion")
expect(!AISubtitleSuggestionPolicy.shouldPresent(scheduledMediaURL: suggestionMediaURL,
                                                 currentMediaURL: URL(fileURLWithPath: "/tmp/other.mov"),
                                                 isPlaybackActive: true,
                                                 hasAudioTracks: true,
                                                 hasSubtitleTracks: false,
                                                 hasExportableAISubtitles: false)
       && !AISubtitleSuggestionPolicy.shouldPresent(scheduledMediaURL: suggestionMediaURL,
                                                    currentMediaURL: suggestionMediaURL,
                                                    isPlaybackActive: false,
                                                    hasAudioTracks: true,
                                                    hasSubtitleTracks: false,
                                                    hasExportableAISubtitles: false)
       && !AISubtitleSuggestionPolicy.shouldPresent(scheduledMediaURL: suggestionMediaURL,
                                                    currentMediaURL: suggestionMediaURL,
                                                    isPlaybackActive: true,
                                                    hasAudioTracks: false,
                                                    hasSubtitleTracks: false,
                                                    hasExportableAISubtitles: false),
       "Stale, inactive, or silent media should not show the AI subtitle suggestion")
expect(AISubtitleAutoMode.always.shouldStart(hasSubtitleTracks: true, hasCompleteAIResult: false)
       && AISubtitleAutoMode.whenMissing.shouldStart(hasSubtitleTracks: false, hasCompleteAIResult: false)
       && !AISubtitleAutoMode.whenMissing.shouldStart(hasSubtitleTracks: true, hasCompleteAIResult: false)
       && !AISubtitleAutoMode.manual.shouldStart(hasSubtitleTracks: false, hasCompleteAIResult: false)
       && !AISubtitleAutoMode.always.shouldStart(hasSubtitleTracks: false, hasCompleteAIResult: true),
       "Automatic generation modes should respect existing subtitles and reusable complete results")
let initializationSuiteName = "ai-subtitle-initialization-\(UUID().uuidString)"
let initializationDefaults = UserDefaults(suiteName: initializationSuiteName)!
defer { initializationDefaults.removePersistentDomain(forName: initializationSuiteName) }
let featureState = AISubtitleFeatureState(userDefaults: initializationDefaults,
                                          systemSupported: true)
expect(!featureState.isEnabled,
       "AI subtitles should be off before first-time setup")
let livePreviewState = AISubtitleLivePreviewState(userDefaults: initializationDefaults)
expect(!livePreviewState.isEnabled,
       "Showing partial subtitles should remain opt-in")
livePreviewState.setEnabled(true)
expect(livePreviewState.isEnabled,
       "The live subtitle preference should persist independently of initialization")
let localInitialization = AISubtitleInitializationState(userDefaults: initializationDefaults,
                                                        credentialChecker: TestCredentials(providers: []),
                                                        consentChecker: TestConsent(providers: []),
                                                        systemSupported: true)
expect(!localInitialization.isComplete,
       "AI subtitle initialization should remain incomplete until setup succeeds")
initializationDefaults.set(0, forKey: "aiSubtitle.provider")
initializationDefaults.set("ja", forKey: "aiSubtitle.sourceLanguage")
initializationDefaults.set("zh-Hans", forKey: "aiSubtitle.targetLanguage")
localInitialization.markComplete(provider: .apple)
expect(localInitialization.isComplete && localInitialization.provider == .apple,
       "Successful local setup should persist the selected first-release provider")
expect(featureState.isEnabled,
       "Completing setup should enable AI subtitles")
featureState.setEnabled(false)
expect(!featureState.isEnabled && localInitialization.isComplete,
       "The global switch should disable generation without discarding setup")
featureState.setEnabled(true)
initializationDefaults.set("en", forKey: "aiSubtitle.sourceLanguage")
expect(localInitialization.isComplete,
       "Changing Apple language defaults should not repeat the one-time setup")
initializationDefaults.set("ja", forKey: "aiSubtitle.sourceLanguage")
localInitialization.reset()
initializationDefaults.set(0, forKey: "aiSubtitle.provider")
initializationDefaults.set("ja", forKey: "aiSubtitle.sourceLanguage")
initializationDefaults.set("zh-Hans", forKey: "aiSubtitle.targetLanguage")
initializationDefaults.set(true, forKey: AISubtitleInitializationState.completedDefaultsKey)
initializationDefaults.set(AISubtitleProviderID.apple.rawValue,
                           forKey: AISubtitleInitializationState.providerDefaultsKey)
expect(localInitialization.isComplete
       && initializationDefaults.stringArray(forKey: AISubtitleInitializationState.enabledProvidersDefaultsKey) == ["apple"],
       "Legacy Apple initialization should migrate without prompting again")
localInitialization.reset()
let remoteWithoutConsent = AISubtitleInitializationState(userDefaults: initializationDefaults,
                                                         credentialChecker: TestCredentials(providers: [.openAI]),
                                                         consentChecker: TestConsent(providers: []),
                                                         systemSupported: true)
initializationDefaults.set(1, forKey: "aiSubtitle.provider")
remoteWithoutConsent.markComplete(provider: .openAI)
expect(!remoteWithoutConsent.isComplete,
       "Remote setup should remain incomplete without cloud-processing consent")
let readyRemoteInitialization = AISubtitleInitializationState(userDefaults: initializationDefaults,
                                                              credentialChecker: TestCredentials(providers: [.openAI]),
                                                              consentChecker: TestConsent(providers: [.openAI]),
                                                              systemSupported: true)
expect(readyRemoteInitialization.isComplete,
       "Remote setup should complete only when credentials and consent are both available")
initializationDefaults.set(2, forKey: "aiSubtitle.provider")
expect(!readyRemoteInitialization.isComplete,
       "Initialization should not apply to a different selected provider")
initializationDefaults.set(1, forKey: "aiSubtitle.provider")
readyRemoteInitialization.reset(provider: .openAI)
expect(!readyRemoteInitialization.isComplete,
       "Removing one remote provider should disable only that provider")
initializationDefaults.set(0, forKey: "aiSubtitle.provider")
localInitialization.markComplete(provider: .apple)
initializationDefaults.set(1, forKey: "aiSubtitle.provider")
readyRemoteInitialization.markComplete(provider: .openAI)
initializationDefaults.set(0, forKey: "aiSubtitle.provider")
expect(localInitialization.isComplete,
       "Switching back to an enabled local provider should not repeat setup")
readyRemoteInitialization.reset()
readyRemoteInitialization.markComplete(provider: .whisperCpp)
expect(!readyRemoteInitialization.isComplete && readyRemoteInitialization.provider == nil,
       "whisper.cpp should not be selectable in the first-release initialization flow")
expect(AISubtitleLocaleReservationPolicy.releaseOrder(
  reservedLocales: ["en", "ja", "ko", "fr", "es"].map(AISubtitleLanguage.init),
  requestedLocale: AISubtitleLanguage("de"),
  preferRequestedLanguage: false
).first == AISubtitleLanguage("en"),
       "A new Apple speech language should release one old reservation at the system limit")
expect(AISubtitleLocaleReservationPolicy.releaseOrder(
  reservedLocales: ["en-US", "ja", "ko", "fr", "es"].map(AISubtitleLanguage.init),
  requestedLocale: AISubtitleLanguage("en"),
  preferRequestedLanguage: false
).first == AISubtitleLanguage("ja"),
       "A failed full-capacity reservation should prefer releasing another language")
expect(AISubtitleLocaleReservationPolicy.releaseOrder(
  reservedLocales: ["en-US"].map(AISubtitleLanguage.init),
  requestedLocale: AISubtitleLanguage("en"),
  preferRequestedLanguage: true
).first == AISubtitleLanguage("en-US"),
       "A stale equivalent Apple speech reservation should remain recoverable")
let noAssets = TestAssets(whisperBinaryURL: nil, whisperModelURL: nil)
expect(AISubtitleProviderID(preferenceIndex: 0) == .apple &&
       AISubtitleProviderID(preferenceIndex: 3) == .whisperCpp &&
       AISubtitleProviderID(preferenceIndex: 4) == nil,
       "Saved provider indices should map deterministically")
let swiftTaskBag = AISubtitleSwiftTaskBag()
let completedTaskIdentifier = swiftTaskBag.reserve()
let completedTaskSignal = DispatchSemaphore(value: 0)
let completedSwiftTask = Task {
  swiftTaskBag.remove(completedTaskIdentifier)
  completedTaskSignal.signal()
}
expect(completedTaskSignal.wait(timeout: .now() + 1) == .success,
       "The Swift task bag race test should complete its task")
swiftTaskBag.attach(completedSwiftTask, to: completedTaskIdentifier)
expect(swiftTaskBag.activeTaskCount == 0,
       "A Swift task completing before registration should not remain retained")
let applePlan = AISubtitleCapabilityDetector(
  platform: AISubtitlePlatform(majorVersion: 26, minorVersion: 5, patchVersion: 0, architecture: "arm64"),
  credentialChecker: TestCredentials(providers: [.openAI]),
  assetLocator: noAssets
).recommendedPlan(for: request)
expect(applePlan.transcriber == .apple && applePlan.translator == .apple,
       "Apple should be preferred on macOS 26")

let oldMac = AISubtitlePlatform(majorVersion: 15, minorVersion: 0, patchVersion: 0, architecture: "arm64")
let cloudPlan = AISubtitleCapabilityDetector(platform: oldMac,
                                             credentialChecker: TestCredentials(providers: [.aliyun]),
                                             assetLocator: noAssets)
  .recommendedPlan(for: request)
expect(cloudPlan.transcriber == .aliyun && cloudPlan.translator == .aliyun,
       "A configured cloud provider should be selected when Apple is unavailable")

let transcript = [
  AISubtitleSegment(id: "1", timeRange: AISubtitleTimeRange(start: 0, end: 2), text: " Hello "),
  AISubtitleSegment(id: "2", timeRange: AISubtitleTimeRange(start: 1.8, end: 3), text: "Hello"),
  AISubtitleSegment(id: "3", timeRange: AISubtitleTimeRange(start: 3.05, end: 4), text: "world")
]
let cues = AISubtitleTimelineAssembler().assemble(transcript, targetLanguage: english)
expect(cues.count == 2
       && cues[0].text == "Hello"
       && cues[0].timeRange.end == 3
       && cues[1].text == "world",
       "Timeline assembly should deduplicate overlap without merging adjacent speech turns")
let repeatedTurnCues = AISubtitleTimelineAssembler().assemble([
  AISubtitleSegment(id: "speaker-a", timeRange: AISubtitleTimeRange(start: 5, end: 6), text: "Yes"),
  AISubtitleSegment(id: "speaker-b", timeRange: AISubtitleTimeRange(start: 6.05, end: 7), text: "Yes")
], targetLanguage: english)
expect(repeatedTurnCues.count == 2,
       "Consecutive speakers saying the same words should remain separate when their timings do not overlap")
let punctuationCues = AISubtitleTimelineAssembler().assemble([
  AISubtitleSegment(id: "punctuation-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 1),
                    text: "Hello"),
  AISubtitleSegment(id: "punctuation-2",
                    timeRange: AISubtitleTimeRange(start: 1, end: 1.2),
                    text: ".")
], targetLanguage: english)
let punctuationSpacingCues = AISubtitleTimelineAssembler().assemble([
  AISubtitleSegment(id: "punctuation-spacing",
                    timeRange: AISubtitleTimeRange(start: 0, end: 1),
                    text: "Hello .")
], targetLanguage: english)
expect(punctuationCues.count == 1 && punctuationCues[0].text == "Hello"
       && punctuationSpacingCues.first?.text == "Hello",
       "Timeline assembly should merge standalone punctuation cues and remove trailing punctuation")
let trailingPunctuationCues = AISubtitleTimelineAssembler().assemble([
  AISubtitleSegment(id: "trailing-punctuation-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 1),
                    text: "你好吗？"),
  AISubtitleSegment(id: "trailing-punctuation-2",
                    timeRange: AISubtitleTimeRange(start: 1.1, end: 2),
                    text: "我很好。"),
  AISubtitleSegment(id: "trailing-punctuation-3",
                    timeRange: AISubtitleTimeRange(start: 2.1, end: 3),
                    text: "他说：\u{201C}你好。\u{201D}")
], targetLanguage: chinese)
expect(trailingPunctuationCues.map(\.text) == ["你好吗", "我很好", "他说：\u{201C}你好\u{201D}"],
       "Every generated subtitle cue should omit sentence-ending punctuation")
let leadingPunctuationCues = AISubtitleTimelineAssembler().assemble([
  AISubtitleSegment(id: "leading-punctuation-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 1),
                    text: "，你好。"),
  AISubtitleSegment(id: "leading-punctuation-2",
                    timeRange: AISubtitleTimeRange(start: 1.1, end: 2),
                    text: "...Welcome!")
], targetLanguage: chinese)
expect(leadingPunctuationCues.map(\.text) == ["你好", "Welcome"],
       "Generated subtitle cues should omit punctuation at both line edges")
let fillerCues = AISubtitleTimelineAssembler().assemble([
  AISubtitleSegment(id: "filler-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 0.25),
                    text: "嗯"),
  AISubtitleSegment(id: "filler-2",
                    timeRange: AISubtitleTimeRange(start: 0.35, end: 0.6),
                    text: "啊"),
  AISubtitleSegment(id: "filler-3",
                    timeRange: AISubtitleTimeRange(start: 0.75, end: 1),
                    text: "嗯")
], targetLanguage: chinese)
expect(fillerCues.count == 1
       && fillerCues[0].text == "嗯 啊 嗯"
       && fillerCues[0].timeRange == AISubtitleTimeRange(start: 0, end: 1),
       "Adjacent short filler sounds should remain readable instead of flashing as separate cues")
let japanese = AISubtitleLanguage("ja")
let fragmentedJapanese = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "fragment-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 0.2),
                    text: "最",
                    language: japanese),
  AISubtitleSegment(id: "fragment-2",
                    timeRange: AISubtitleTimeRange(start: 0.25, end: 1.8),
                    text: "近なんか気になることがあって",
                    language: japanese),
  AISubtitleSegment(id: "fragment-3",
                    timeRange: AISubtitleTimeRange(start: 2.5, end: 2.7),
                    text: "検",
                    language: japanese),
  AISubtitleSegment(id: "fragment-4",
                    timeRange: AISubtitleTimeRange(start: 2.75, end: 4.1),
                    text: "証したいと思いま",
                    language: japanese),
  AISubtitleSegment(id: "fragment-5",
                    timeRange: AISubtitleTimeRange(start: 4.15, end: 4.3),
                    text: "す",
                    language: japanese)
], language: japanese)
expect(fragmentedJapanese.count == 2
       && fragmentedJapanese[0].text == "最近なんか気になることがあって"
       && fragmentedJapanese[1].text == "検証したいと思います",
       "Speech-recognition fragments should become complete short phrases before translation")
let longTimedJapaneseSuffix = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "timed-fragment-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 1.74),
                    text: "素晴らし",
                    language: japanese),
  AISubtitleSegment(id: "timed-fragment-2",
                    timeRange: AISubtitleTimeRange(start: 1.74, end: 3.84),
                    text: "い",
                    language: japanese)
], language: japanese)
expect(longTimedJapaneseSuffix.count == 1 && longTimedJapaneseSuffix[0].text == "素晴らしい",
       "A single-character grammatical suffix should merge even when speech timing is imprecise")
let unstableJapaneseWord = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "unstable-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 0.6),
                    text: "や",
                    language: japanese),
  AISubtitleSegment(id: "unstable-2",
                    timeRange: AISubtitleTimeRange(start: 0.6, end: 1.14),
                    text: "ってきました",
                    language: japanese),
  AISubtitleSegment(id: "unstable-3",
                    timeRange: AISubtitleTimeRange(start: 1.14, end: 2.46),
                    text: "ね",
                    language: japanese)
], language: japanese)
expect(unstableJapaneseWord.count == 1 && unstableJapaneseWord[0].text == "やってきましたね",
       "Contiguous unstable speech results should be reassembled before translation")
let floatingOverlapJapaneseWord = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "floating-overlap-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 2.28000000000001),
                    text: "検証したいと思いま",
                    language: japanese),
  AISubtitleSegment(id: "floating-overlap-2",
                    timeRange: AISubtitleTimeRange(start: 2.28, end: 3.6),
                    text: "す",
                    language: japanese)
], language: japanese)
expect(floatingOverlapJapaneseWord.count == 1
       && floatingOverlapJapaneseWord[0].text == "検証したいと思います",
       "Tiny floating-point overlaps must not prevent grammatical fragments from merging")
let recoveredJapanesePhrase = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "school-fragment-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 1.62),
                    text: "あの高",
                    language: japanese),
  AISubtitleSegment(id: "school-fragment-2",
                    timeRange: AISubtitleTimeRange(start: 1.62, end: 5.58),
                    text: "校はそのな",
                    language: japanese),
  AISubtitleSegment(id: "school-fragment-3",
                    timeRange: AISubtitleTimeRange(start: 5.58, end: 9.18),
                    text: "んというか",
                    language: japanese)
], language: japanese)
expect(recoveredJapanesePhrase.map(\.text).joined() == "あの高校はそのなんというか"
       && !recoveredJapanesePhrase.dropLast().contains { $0.text.hasSuffix("高") || $0.text.hasSuffix("な") }
       && !recoveredJapanesePhrase.dropFirst().contains { $0.text.hasPrefix("校") || $0.text.hasPrefix("ん") },
       "Speech fragments should be rejoined before contextual blocks are split at Japanese word boundaries")
let recoveredLongJapaneseSuffix = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "long-suffix-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 12.78),
                    text: "あの高校はそのなんというかそのヤンキーが結構多",
                    language: japanese),
  AISubtitleSegment(id: "long-suffix-2",
                    timeRange: AISubtitleTimeRange(start: 12.78, end: 14.28),
                    text: "く",
                    language: japanese)
], language: japanese)
expect(recoveredLongJapaneseSuffix.map(\.text).joined() == "あの高校はそのなんというかそのヤンキーが結構多く"
       && !recoveredLongJapaneseSuffix.dropLast().contains { $0.text.hasSuffix("多") }
       && !recoveredLongJapaneseSuffix.dropFirst().contains { $0.text.hasPrefix("く") },
       "A trailing Japanese inflection should be recovered before the longer text is divided into translation blocks")
let recoveredColloquialJapanese = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "colloquial-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 1.4),
                    text: "全然まあ話も盛り上がっ",
                    language: japanese),
  AISubtitleSegment(id: "colloquial-2",
                    timeRange: AISubtitleTimeRange(start: 1.4, end: 4.1),
                    text: "ちゃったらもうちょっと飲めちゃうかなみたいな",
                    language: japanese)
], language: japanese)
expect(recoveredColloquialJapanese.count == 1
       && recoveredColloquialJapanese[0].text.contains("盛り上がっちゃったら"),
       "Japanese colloquial contractions should not split before ちゃ")
let recoveredJapaneseAcknowledgement = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "acknowledgement-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 1.1),
                    text: "感じなんですけどな",
                    language: japanese),
  AISubtitleSegment(id: "acknowledgement-2",
                    timeRange: AISubtitleTimeRange(start: 1.1, end: 3.2),
                    text: "るほどであのね結構ねあの",
                    language: japanese)
], language: japanese)
expect(recoveredJapaneseAcknowledgement.count == 1
       && recoveredJapaneseAcknowledgement[0].text.contains("なるほど"),
       "A split Japanese acknowledgement should be restored before translation")
let repeatedJapaneseRecognitionTail = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "tail-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 4.68),
                    text: "巨乳伝巨乳伝巨乳伝でででポピーンって感じですよ",
                    language: japanese),
  AISubtitleSegment(id: "tail-2",
                    timeRange: AISubtitleTimeRange(start: 4.68, end: 5.01),
                    text: "ピーンって感じですよ",
                    language: japanese)
], language: japanese)
expect(repeatedJapaneseRecognitionTail.count == 1
       && repeatedJapaneseRecognitionTail[0].text == "巨乳伝巨乳伝巨乳伝でででポピーンって感じですよ",
       "A very short repeated recognition suffix should not flash as a separate subtitle")
let overlappingEnglishRevision = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "revision-1",
                    timeRange: AISubtitleTimeRange(start: 2045.76, end: 2048.998875),
                    text: "It's all right. You're just worried I'm quicker than you. Hi, I'm...",
                    language: english),
  AISubtitleSegment(id: "revision-2",
                    timeRange: AISubtitleTimeRange(start: 2047.5, end: 2049.36),
                    text: "Quicker than you. Hi, I'm Sonny.",
                    language: english)
], language: english)
expect(overlappingEnglishRevision.count == 1
       && overlappingEnglishRevision[0].text.contains("Hi, I'm Sonny."),
       "An overlapping speech revision should append only its new words instead of flashing the repeated phrase")
let inflectedEnglishRevision = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "corner-1",
                    timeRange: AISubtitleTimeRange(start: 1519.14, end: 1522.4989375),
                    text: "But definitely snapping the high speed corner.",
                    language: english),
  AISubtitleSegment(id: "corner-2",
                    timeRange: AISubtitleTimeRange(start: 1521, end: 1522.8),
                    text: "Snapping the high speed corners.",
                    language: english)
], language: english)
expect(inflectedEnglishRevision.count == 1,
       "Minor inflection changes in an overlapping speech revision should not create a duplicate cue")
let oneWordEnglishRevision = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "records-1",
                    timeRange: AISubtitleTimeRange(start: 5966.82, end: 5968.498875),
                    text: "the... records.",
                    language: english),
  AISubtitleSegment(id: "records-2",
                    timeRange: AISubtitleTimeRange(start: 5967, end: 5968.62),
                    text: "records.",
                    language: english)
], language: english)
expect(oneWordEnglishRevision.count == 1,
       "A one-word suffix revision should be absorbed when its recognition window substantially overlaps")
let longJapaneseContext = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "long-context",
                    timeRange: AISubtitleTimeRange(start: 0, end: 18),
                    text: "今日は来てくれてありがとうございます。まず少しお話を聞かせてください。場所はすぐ近くです。時間は十分くらいです。大丈夫ですか。",
                    language: japanese)
], language: japanese)
expect(longJapaneseContext.count >= 3
       && longJapaneseContext.allSatisfy { $0.timeRange.duration <= 8.01 }
       && longJapaneseContext.allSatisfy { $0.text.count <= 48 },
       "Long recognition results should become contextual translation blocks instead of one oversized request")
expect(longJapaneseContext.contains { AISubtitleTextPartitioner().sentenceEndCount(in: $0.text) > 1 },
       "Translation blocks should retain nearby sentence context when it fits")
let meaningfulTurns = AISubtitleSemanticSegmenter().assemble([
  AISubtitleSegment(id: "turn-1",
                    timeRange: AISubtitleTimeRange(start: 5, end: 6),
                    text: "Yes",
                    language: english),
  AISubtitleSegment(id: "turn-2",
                    timeRange: AISubtitleTimeRange(start: 6.05, end: 7),
                    text: "Yes",
                    language: english)
], language: english)
expect(meaningfulTurns.count == 2,
       "Semantic segmentation must not merge two normal adjacent speech turns")
let longChineseCues = AISubtitleTimelineAssembler().assemble([
  AISubtitleSegment(id: "long-chinese",
                    timeRange: AISubtitleTimeRange(start: 10, end: 22),
                    text: "接近光速宇宙飞船？让它比任何人造物体旅行得更远。此时拜访一颗星星，只是为了看看是什么起来？是的。")
], targetLanguage: chinese)
expect(longChineseCues.count == 4
       && longChineseCues.allSatisfy { $0.text.count <= 26 }
       && longChineseCues.first?.timeRange.start == 10
       && longChineseCues.last?.timeRange.end == 22
       && zip(longChineseCues, longChineseCues.dropFirst()).allSatisfy {
         $0.timeRange.end == $1.timeRange.start
       },
       "Long translated speech should be split at sentence boundaries with continuous timing")
let unpunctuatedChineseCues = AISubtitleTimelineAssembler().assemble([
  AISubtitleSegment(id: "long-unpunctuated",
                    timeRange: AISubtitleTimeRange(start: 0, end: 9),
                    text: String(repeating: "字幕内容", count: 12))
], targetLanguage: chinese)
expect(unpunctuatedChineseCues.count > 1
       && unpunctuatedChineseCues.allSatisfy { $0.text.count <= 26 },
       "A single oversized speech segment should be split even without punctuation")
let writer = AISubtitleFileWriter()
expect(writer.string(for: cues, format: .webVTT).contains("00:00:03.050 --> 00:00:04.000\nworld"),
       "WebVTT timestamps should be valid")
expect(writer.string(for: cues, format: .srt).contains("00:00:03,050 --> 00:00:04,000\nworld"),
       "SRT timestamps should be valid")

let store = AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: tempRoot))
let key = AISubtitleCacheKey(media: media,
                             transcriberID: .apple,
                             translatorID: .apple,
                             transcriberModelIdentifier: "speech-v1",
                             translatorModelIdentifier: "translation-v1")
var secondAudioTrackMedia = media
secondAudioTrackMedia.audioTrackID = 2
secondAudioTrackMedia.audioStreamIndex = 1
let secondAudioTrackKey = AISubtitleCacheKey(media: secondAudioTrackMedia,
                                             transcriberID: .apple,
                                             translatorID: .apple,
                                             transcriberModelIdentifier: "speech-v1",
                                             translatorModelIdentifier: "translation-v1")
expect(secondAudioTrackKey.stableIdentifier != key.stableIdentifier,
       "Different audio tracks in the same media must use isolated subtitle caches")
let artifacts = try AISubtitleFilePipeline(cacheStore: store).prepare(transcript: transcript,
                                                                       targetLanguage: english,
                                                                       cacheKey: key)
expect(store.cachedVTT(for: key) == artifacts.translatedVTTURL,
       "Committed cache should be discoverable")
let semanticCache = try store.cachedContent(for: key)
expect(semanticCache.transcript.map(\.id) == transcript.map(\.id)
       && semanticCache.cues.map(\.id) == transcript.map(\.id),
       "Resumable cache data should preserve semantic cue IDs before display splitting")
expect(FileManager.default.fileExists(atPath: artifacts.originalVTTURL.path)
       && FileManager.default.fileExists(atPath: artifacts.originalSRTURL.path)
       && FileManager.default.fileExists(atPath: artifacts.translatedSRTURL.path),
       "A committed cache should contain original-language and translated subtitle files")
let pairedTranscript = [
  AISubtitleSegment(id: "paired-1",
                    timeRange: AISubtitleTimeRange(start: 0, end: 0.4),
                    text: "字幕を読む",
                    language: japanese),
  AISubtitleSegment(id: "paired-2",
                    timeRange: AISubtitleTimeRange(start: 3, end: 4),
                    text: "次の台詞",
                    language: japanese)
]
let pairedTranslations = [
  AISubtitleCue(id: "paired-1",
                timeRange: AISubtitleTimeRange(start: 0.1, end: 0.2),
                text: "请阅读这条比较长的字幕内容",
                language: chinese),
  AISubtitleCue(id: "paired-2",
                timeRange: AISubtitleTimeRange(start: 20, end: 30),
                text: "下一句",
                language: chinese)
]
let pairedTimeline = AISubtitlePairedTimelineAssembler().assemble(
  transcript: pairedTranscript,
  translatedCues: pairedTranslations,
  sourceLanguage: japanese,
  targetLanguage: chinese)
expect(pairedTimeline.originalCues.map(\.timeRange) == pairedTimeline.translatedCues.map(\.timeRange)
       && pairedTimeline.originalCues.count == pairedTimeline.translatedCues.count,
       "Original and translated subtitles must use one shared cue timeline")
expect(pairedTimeline.originalCues[0].timeRange.end > 0.4
       && pairedTimeline.originalCues[0].timeRange.end <= 3,
       "A short cue should use available silence to provide a readable display duration")
let pairedOriginalSRT = writer.string(for: pairedTimeline.originalCues, format: .srt)
let pairedTranslatedSRT = writer.string(for: pairedTimeline.translatedCues, format: .srt)
let pairedOriginalTimestamps = pairedOriginalSRT.components(separatedBy: .newlines)
  .filter { $0.contains(" --> ") }
let pairedTranslatedTimestamps = pairedTranslatedSRT.components(separatedBy: .newlines)
  .filter { $0.contains(" --> ") }
expect(pairedOriginalTimestamps == pairedTranslatedTimestamps,
       "Both exported SRT files must contain exactly the same timestamp rows")
let longDisplayTimeline = AISubtitlePairedTimelineAssembler().assemble(
  transcript: [AISubtitleSegment(
    id: "long-display",
    timeRange: AISubtitleTimeRange(start: 10, end: 22),
    text: "学校の話を聞きました。昔はいろいろありました。今は落ち着いています。もう少し話しましょう。",
    language: japanese)],
  translatedCues: [AISubtitleCue(
    id: "long-display",
    timeRange: AISubtitleTimeRange(start: 10, end: 22),
    text: "聊到了学校的事情。以前发生过很多事。现在已经安定下来了。我们再聊一会儿吧。",
    language: chinese)],
  sourceLanguage: japanese,
  targetLanguage: chinese)
expect(longDisplayTimeline.originalCues.count >= 3
       && longDisplayTimeline.originalCues.count == longDisplayTimeline.translatedCues.count
       && longDisplayTimeline.originalCues.map(\.timeRange)
         == longDisplayTimeline.translatedCues.map(\.timeRange)
       && longDisplayTimeline.originalCues.allSatisfy { $0.text.components(separatedBy: .newlines).count <= 2 }
       && longDisplayTimeline.translatedCues.allSatisfy { $0.text.components(separatedBy: .newlines).count <= 2 },
       "A contextual translation block should become several readable, synchronized display cues")
let japaneseGrammarTimeline = AISubtitlePairedTimelineAssembler().assemble(
  transcript: [AISubtitleSegment(
    id: "japanese-grammar",
    timeRange: AISubtitleTimeRange(start: 0, end: 6),
    text: "あのー。結構はい初体験とかって早かったんじゃないですか。めちゃめちゃ早かったですよ",
    language: japanese)],
  translatedCues: [AISubtitleCue(
    id: "japanese-grammar",
    timeRange: AISubtitleTimeRange(start: 0, end: 6),
    text: "那个。没关系。第一次体验不是太快了吗。太快了。",
    language: chinese)],
  sourceLanguage: japanese,
  targetLanguage: chinese)
let japaneseDisplayText = japaneseGrammarTimeline.originalCues.map(\.text)
expect(japaneseGrammarTimeline.originalCues.count == japaneseGrammarTimeline.translatedCues.count
       && !japaneseDisplayText.contains { $0.hasSuffix("早かっ") }
       && !japaneseDisplayText.contains { $0.hasPrefix("たん") },
       "Synchronized display splitting must not cut Japanese conjugations to match translated sentence counts")
let japaneseLineParts = AISubtitleTextPartitioner().balancedParts(
  "セックスをすることが早ければ早いほど良くないみたいな",
  count: 2,
  compact: true,
  language: japanese)
expect(japaneseLineParts.count == 2
       && !japaneseLineParts[0].hasSuffix("早けれ")
       && !japaneseLineParts[1].hasPrefix("ば"),
       "Japanese two-line wrapping should keep conditional inflections together")
let balancedEnglishLineTimeline = AISubtitlePairedTimelineAssembler().assemble(
  transcript: [AISubtitleSegment(
    id: "balanced-english-lines",
    timeRange: AISubtitleTimeRange(start: 0, end: 6),
    text: "綺麗だと若い頃は無茶なことをされたと思うんですよ",
    language: japanese)],
  translatedCues: [AISubtitleCue(
    id: "balanced-english-lines",
    timeRange: AISubtitleTimeRange(start: 0, end: 6),
    text: "If you're beautiful, I think you did something reckless when you were young",
    language: english)],
  sourceLanguage: japanese,
  targetLanguage: english)
let balancedEnglishLines = balancedEnglishLineTimeline.translatedCues[0].text
  .components(separatedBy: .newlines)
expect(balancedEnglishLines.count == 2
       && balancedEnglishLines.allSatisfy { $0.count <= 42 }
       && abs(balancedEnglishLines[0].count - balancedEnglishLines[1].count) <= 8,
       "Latin subtitles should wrap into two balanced readable lines instead of favoring distant punctuation")
let f1LongExchangeTimeline = AISubtitlePairedTimelineAssembler().assemble(
  transcript: [AISubtitleSegment(
    id: "f1-long-exchange",
    timeRange: AISubtitleTimeRange(start: 5266.26, end: 5271.36),
    text: "If you pull that shit again, I will knock your teeth out. Oh, no one gets past us without a fight, right? Oh, is this funny?",
    language: english)],
  translatedCues: [AISubtitleCue(
    id: "f1-long-exchange",
    timeRange: AISubtitleTimeRange(start: 5266.26, end: 5271.36),
    text: "またあんなクソを引っ張ったら、歯をぶっ飛ばす。ああ、誰も戦わずに私たちを通り過ぎることはありませんよね？あら、これは面白いですか？",
    language: japanese)],
  sourceLanguage: english,
  targetLanguage: japanese)
expect(f1LongExchangeTimeline.originalCues.count >= 2,
       "A dense English-Japanese exchange should split into multiple display cues")
expect(f1LongExchangeTimeline.originalCues.count == f1LongExchangeTimeline.translatedCues.count
       && f1LongExchangeTimeline.originalCues.map(\.timeRange)
         == f1LongExchangeTimeline.translatedCues.map(\.timeRange),
       "A dense English-Japanese exchange should keep an exact shared timeline")
expect(f1LongExchangeTimeline.originalCues.allSatisfy {
  $0.text.components(separatedBy: .newlines).count <= 2
    && $0.text.components(separatedBy: .newlines).allSatisfy { $0.count <= 42 }
}, "Dense English display cues should stay within two 42-character lines")
expect(f1LongExchangeTimeline.translatedCues.allSatisfy {
  $0.text.components(separatedBy: .newlines).count <= 2
    && $0.text.components(separatedBy: .newlines).allSatisfy { $0.count <= 22 }
}, "Dense Japanese display cues should stay within two 22-character lines")
let repeatedPunctuationTimeline = AISubtitlePairedTimelineAssembler().assemble(
  transcript: [AISubtitleSegment(id: "repeated-punctuation",
                                 timeRange: AISubtitleTimeRange(start: 0, end: 2),
                                 text: "本当に出ました。そうでしょう",
                                 language: japanese)],
  translatedCues: [AISubtitleCue(id: "repeated-punctuation",
                                 timeRange: AISubtitleTimeRange(start: 0, end: 2),
                                 text: "真的出来了。。 是吧",
                                 language: chinese)],
  sourceLanguage: japanese,
  targetLanguage: chinese)
expect(repeatedPunctuationTimeline.translatedCues.map(\.text) == ["真的出来了。是吧"],
       "Generated subtitles should collapse duplicated punctuation and compact CJK spacing")
let stretchedDisplayTimeline = AISubtitlePairedTimelineAssembler().assemble(
  transcript: [AISubtitleSegment(id: "stretched",
                                 timeRange: AISubtitleTimeRange(start: 0, end: 12),
                                 text: "あ",
                                 language: japanese)],
  translatedCues: [AISubtitleCue(id: "stretched",
                                 timeRange: AISubtitleTimeRange(start: 0, end: 12),
                                 text: "啊",
                                 language: chinese)],
  sourceLanguage: japanese,
  targetLanguage: chinese)
expect(stretchedDisplayTimeline.originalCues.first?.timeRange.duration == 6
       && stretchedDisplayTimeline.translatedCues.first?.timeRange.duration == 6,
       "A short subtitle should not linger longer than the maximum readable display duration")
expect(store.isComplete(for: key, mediaDuration: 4),
       "A cache covering the full media duration should be complete")
let incompleteCoverageKey = AISubtitleCacheKey(media: media,
                                               transcriberID: .apple,
                                               translatorID: .apple,
                                               transcriberModelIdentifier: "incomplete-coverage")
_ = try store.save(transcript: transcript,
                   cues: cues,
                   coveredRanges: [AISubtitleTimeRange(start: 50, end: 150)],
                   for: incompleteCoverageKey)
expect(store.completionProgress(for: incompleteCoverageKey, mediaDuration: 100) == 0.5
       && !store.isComplete(for: incompleteCoverageKey, mediaDuration: 100),
       "Coverage outside the media bounds must not make an incomplete video report 100 percent")

let sidecarDirectory = tempRoot.deletingLastPathComponent()
  .appendingPathComponent("ai-subtitle-sidecars-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: sidecarDirectory) }
try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
let sidecarMediaURL = sidecarDirectory.appendingPathComponent("Example Movie.mp4")
try Data().write(to: sidecarMediaURL)
let sidecarFiles = try AISubtitleSidecarPublisher().publish(artifacts: artifacts,
                                                            key: key,
                                                            mediaURL: sidecarMediaURL)
expect(sidecarFiles.originalURL.lastPathComponent == "Example Movie.rawya-ai.en.srt"
       && sidecarFiles.translatedURL?.lastPathComponent == "Example Movie.rawya-ai.zh-hans.srt"
       && sidecarFiles.allURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
       "Completed translated subtitles should publish stable source and target SRT sidecars")
let unrelatedSidecar = sidecarDirectory.appendingPathComponent("Example Movie.custom.srt")
try Data("keep".utf8).write(to: unrelatedSidecar)
var japaneseSidecarMedia = media
japaneseSidecarMedia.targetLanguage = japanese
let japaneseSidecarKey = AISubtitleCacheKey(media: japaneseSidecarMedia,
                                             transcriberID: .apple,
                                             translatorID: .apple)
let japaneseSidecarFiles = try AISubtitleSidecarPublisher().publish(artifacts: artifacts,
                                                                    key: japaneseSidecarKey,
                                                                    mediaURL: sidecarMediaURL)
expect(sidecarFiles.allURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
       && japaneseSidecarFiles.allURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
       && FileManager.default.fileExists(atPath: unrelatedSidecar.path),
       "Generating a second target language should retain source, both translations, and user subtitle files")
var preciseTimestampMedia = media
preciseTimestampMedia.fileModifiedAt = Date(timeIntervalSince1970: 100.123456789)
let preciseTimestampKey = AISubtitleCacheKey(media: preciseTimestampMedia,
                                             transcriberID: .apple,
                                             translatorID: .apple)
let preciseTimestampRoot = tempRoot.deletingLastPathComponent()
  .appendingPathComponent("ai-subtitle-precise-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: preciseTimestampRoot) }
let preciseTimestampStore = AISubtitleCacheStore(layout: AISubtitleCacheLayout(
  rootURL: preciseTimestampRoot))
let preciseTimestampArtifacts = try AISubtitleFilePipeline(cacheStore: preciseTimestampStore).prepare(
  transcript: transcript,
  targetLanguage: english,
  cacheKey: preciseTimestampKey)
expect(preciseTimestampStore.cachedVTT(for: preciseTimestampKey) == preciseTimestampArtifacts.translatedVTTURL,
       "Cache validation should tolerate JSON date precision below the millisecond cache-key granularity")
expect(AISubtitleCacheKey(media: media,
                          transcriberID: .apple,
                          translatorID: .apple,
                          transcriberModelIdentifier: "speech-v1",
                          translatorModelIdentifier: "translation-v1").stableIdentifier == key.stableIdentifier,
       "Cache identifiers should be deterministic")

let regenerationRoot = tempRoot.deletingLastPathComponent()
  .appendingPathComponent("ai-subtitle-regeneration-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: regenerationRoot) }
let regenerationStore = AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: regenerationRoot))
let legacyTranslatedCue = AISubtitleCue(id: "1",
                                        timeRange: AISubtitleTimeRange(start: 0, end: 4),
                                        text: "Legacy subtitle.",
                                        language: english)
let legacyArtifacts = try regenerationStore.save(transcript: transcript,
                                                  cues: [legacyTranslatedCue],
                                                  coveredRanges: [AISubtitleTimeRange(start: 0, end: 4)],
                                                  for: key)
expect(regenerationStore.cachedArtifacts(for: key) != nil,
       "A completed result should exist before a manual regeneration")
let legacySRT = try String(contentsOf: legacyArtifacts.translatedSRTURL, encoding: .utf8)
expect(legacySRT.contains("Legacy subtitle") && !legacySRT.contains("Legacy subtitle."),
       "New cache writes should immediately apply current subtitle punctuation rules")
let refreshedArtifacts = try regenerationStore.refreshSubtitleFiles(for: key)
let refreshedSRT = try String(contentsOf: refreshedArtifacts.translatedSRTURL, encoding: .utf8)
let refreshedCache = try regenerationStore.cachedContent(for: key)
expect(!refreshedSRT.contains("Legacy subtitle.")
       && refreshedCache.transcript.map(\.id) == transcript.map(\.id)
       && refreshedCache.cues.map(\.id) == [legacyTranslatedCue.id],
       "Restoring a completed cache should update exports without re-splitting cached semantic cues")
try regenerationStore.removeCachedContent(for: key)
expect(regenerationStore.cachedArtifacts(for: key) == nil
       && regenerationStore.completionProgress(for: key, mediaDuration: 4) == 0,
       "Manual regeneration should remove the complete cache and restart from zero")

var alternateMedia = media
alternateMedia.targetLanguage = english
let alternateKey = AISubtitleCacheKey(media: alternateMedia,
                                      transcriberID: .apple,
                                      translatorID: nil)
_ = try AISubtitleFilePipeline(cacheStore: store).prepare(transcript: transcript,
                                                        targetLanguage: english,
                                                        cacheKey: alternateKey)
let beforePrune = try store.usage()
let afterPrune = try store.prune(maximumBytes: 0, excluding: key)
expect(beforePrune.entryCount == 3 && afterPrune.entryCount == 1 && afterPrune.removedEntryCount == 2,
       "Cache pruning should evict inactive entries and preserve the active key")

let plannedRanges = AISubtitleChunkPlanner().ranges(covering: AISubtitleTimeRange(start: 10, end: 140))
expect(plannedRanges == [AISubtitleTimeRange(start: 10, end: 70),
                         AISubtitleTimeRange(start: 68.5, end: 128.5),
                         AISubtitleTimeRange(start: 127, end: 140)],
       "Chunk planning should use 60-second chunks with 1.5-second overlap")

let schedulerRoot = tempRoot.appendingPathComponent("scheduler", isDirectory: true)
let schedulerStore = AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: schedulerRoot))
var sameLanguageMedia = media
sameLanguageMedia.targetLanguage = english
let schedulerKey = AISubtitleCacheKey(media: sameLanguageMedia,
                                      transcriberID: .apple,
                                      translatorID: nil)
let extractor = TestExtractor()
let scheduler = AISubtitleScheduler(extractor: extractor,
                                    transcriber: TestTranscriber(),
                                    translator: AISubtitlePassThroughTranslator(providerID: .apple),
                                    cacheStore: schedulerStore)
let completed = DispatchSemaphore(value: 0)
var schedulerProgressValues: [Double] = []
var completedArtifactCount = 0
scheduler.start(media: sameLanguageMedia,
                mediaDuration: 130,
                cacheKey: schedulerKey,
                playbackPosition: 0,
                stateHandler: {
                  if let progress = $0.progress { schedulerProgressValues.append(progress) }
                  if $0.phase == .completed { completed.signal() }
                },
                subtitleFileHandler: { _ in completedArtifactCount += 1 })
expect(completed.wait(timeout: .now() + 5) == .success && extractor.ranges.count == 3,
       "Scheduler should process the entire video in planned chunks")
expect(completedArtifactCount == 1,
       "Scheduler should publish subtitle artifacts only after full-video generation completes")
expect(schedulerProgressValues.last == 1
       && zip(schedulerProgressValues, schedulerProgressValues.dropFirst()).allSatisfy { pair in pair.0 <= pair.1 },
       "Full-video scheduler progress should be monotonic and reach 100%")
scheduler.cancel()

let livePreviewRoot = tempRoot.appendingPathComponent("live-preview", isDirectory: true)
let livePreviewExtractor = TestExtractor()
let livePreviewScheduler = AISubtitleScheduler(
  extractor: livePreviewExtractor,
  transcriber: TestTranscriber(),
  translator: AISubtitlePassThroughTranslator(providerID: .apple),
  cacheStore: AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: livePreviewRoot)),
  configuration: AISubtitleScheduler.Configuration(
    chunkPlanner: AISubtitleChunkPlanner(chunkDuration: 60, overlapDuration: 0),
    publishesIntermediateArtifacts: true))
let livePreviewCompleted = DispatchSemaphore(value: 0)
var livePreviewArtifactCount = 0
livePreviewScheduler.start(media: sameLanguageMedia,
                           mediaDuration: 130,
                           cacheKey: AISubtitleCacheKey(media: sameLanguageMedia,
                                                        transcriberID: .apple,
                                                        translatorID: nil,
                                                        transcriberModelIdentifier: "live-preview-test"),
                           playbackPosition: 0,
                           stateHandler: { if $0.phase == .completed { livePreviewCompleted.signal() } },
                           subtitleFileHandler: { _ in livePreviewArtifactCount += 1 })
expect(livePreviewCompleted.wait(timeout: .now() + 5) == .success
       && livePreviewArtifactCount == 2,
       "Live preview should publish completed chunks without publishing the final cache twice")
livePreviewScheduler.cancel()

let boundaryRevisionRoot = tempRoot.appendingPathComponent("boundary-revision", isDirectory: true)
let boundaryRevisionStore = AISubtitleCacheStore(layout: AISubtitleCacheLayout(
  rootURL: boundaryRevisionRoot))
let boundaryRevisionKey = AISubtitleCacheKey(
  media: sameLanguageMedia,
  transcriberID: .apple,
  translatorID: nil,
  transcriberModelIdentifier: "boundary-revision-self-test")
let boundaryRevisionScheduler = AISubtitleScheduler(
  extractor: TestExtractor(),
  transcriber: BoundaryRevisionTestTranscriber(),
  translator: AISubtitlePassThroughTranslator(providerID: .apple),
  cacheStore: boundaryRevisionStore)
let boundaryRevisionCompleted = DispatchSemaphore(value: 0)
boundaryRevisionScheduler.start(media: sameLanguageMedia,
                                mediaDuration: 118.5,
                                cacheKey: boundaryRevisionKey,
                                playbackPosition: 0,
                                stateHandler: {
                                  if $0.phase == .completed { boundaryRevisionCompleted.signal() }
                                },
                                subtitleFileHandler: { _ in })
expect(boundaryRevisionCompleted.wait(timeout: .now() + 5) == .success,
       "A cross-chunk speech-revision test should complete")
let boundaryRevisionCache = try boundaryRevisionStore.cachedContent(for: boundaryRevisionKey)
expect(boundaryRevisionCache.transcript.count == 1
       && boundaryRevisionCache.transcript[0].text == "And that's gonna cause damage!"
       && boundaryRevisionCache.cues.count == 1,
       "Overlapping audio chunks should reconcile their speech revisions before translation")
boundaryRevisionScheduler.cancel()

let sameLanguageArtifacts = schedulerStore.cachedArtifacts(for: schedulerKey)!
let sameLanguageSidecars = try AISubtitleSidecarPublisher().publish(artifacts: sameLanguageArtifacts,
                                                                    key: schedulerKey,
                                                                    mediaURL: sidecarMediaURL)
expect(sameLanguageSidecars.translatedURL == nil && sameLanguageSidecars.allURLs.count == 1,
       "Matching source and target languages should publish only one subtitle file")

let endOfFileExtractor = TestExtractor()
let endOfFileScheduler = AISubtitleScheduler(
  extractor: endOfFileExtractor,
  transcriber: TestTranscriber(),
  translator: AISubtitlePassThroughTranslator(providerID: .apple),
  cacheStore: AISubtitleCacheStore(layout: AISubtitleCacheLayout(
    rootURL: tempRoot.appendingPathComponent("end-of-file", isDirectory: true))))
let endOfFileCompleted = DispatchSemaphore(value: 0)
endOfFileScheduler.start(
  media: sameLanguageMedia,
  mediaDuration: 15,
  cacheKey: AISubtitleCacheKey(media: sameLanguageMedia,
                               transcriberID: .apple,
                               translatorID: nil,
                               transcriberModelIdentifier: "end-of-file-test"),
  playbackPosition: 15,
  stateHandler: { if $0.phase == .completed { endOfFileCompleted.signal() } },
  subtitleFileHandler: { _ in })
expect(endOfFileCompleted.wait(timeout: .now() + 5) == .success
       && endOfFileExtractor.ranges == [AISubtitleTimeRange(start: 0, end: 15)],
       "Starting generation at end of file should process the media from the beginning")
endOfFileScheduler.cancel()

let silentTranslator = RejectingTestTranslator()
let silentStore = AISubtitleCacheStore(layout: AISubtitleCacheLayout(
  rootURL: tempRoot.appendingPathComponent("silent-video", isDirectory: true)))
let silentKey = AISubtitleCacheKey(media: sameLanguageMedia,
                                   transcriberID: .apple,
                                   translatorID: nil,
                                   transcriberModelIdentifier: "silent-video-test")
let silentScheduler = AISubtitleScheduler(
  extractor: TestExtractor(),
  transcriber: EmptyTestTranscriber(),
  translator: silentTranslator,
  cacheStore: silentStore)
let silentCompleted = DispatchSemaphore(value: 0)
silentScheduler.start(
  media: sameLanguageMedia,
  mediaDuration: 30,
  cacheKey: silentKey,
  playbackPosition: 0,
  stateHandler: { if $0.phase == .completed { silentCompleted.signal() } },
  subtitleFileHandler: { _ in })
expect(silentCompleted.wait(timeout: .now() + 5) == .success && !silentTranslator.wasCalled,
       "Silent chunks should count as processed without sending an empty translation request")
if let silentArtifacts = silentStore.cachedArtifacts(for: silentKey) {
  do {
    _ = try AISubtitleSidecarPublisher().publish(artifacts: silentArtifacts,
                                                 key: silentKey,
                                                 mediaURL: sidecarMediaURL)
    expect(false, "Silent media should not publish empty subtitle sidecars")
  } catch let error as AISubtitleError {
    expect(error.code == "empty_subtitle_result",
           "Silent media should report an empty subtitle result")
  }
}
silentScheduler.cancel()

expect(!AISubtitleSpeechYieldPolicy.shouldPause(transcriptIsEmpty: true,
                                                processedThrough: 119,
                                                mediaDuration: 600,
                                                hasRemainingRanges: true)
       && AISubtitleSpeechYieldPolicy.shouldPause(transcriptIsEmpty: true,
                                                  processedThrough: 120,
                                                  mediaDuration: 600,
                                                  hasRemainingRanges: true)
       && !AISubtitleSpeechYieldPolicy.shouldPause(transcriptIsEmpty: false,
                                                   processedThrough: 180,
                                                   mediaDuration: 600,
                                                   hasRemainingRanges: true),
       "Low speech yield should pause only after a conservative empty opening")
let overlapPolicySegments = AISubtitleChunkOverlapPolicy.newSpeechSegments([
  AISubtitleSegment(id: "overlap-only",
                    timeRange: AISubtitleTimeRange(start: 58.5, end: 59.9),
                    text: "Repeated overlap",
                    language: english),
  AISubtitleSegment(id: "crosses-boundary",
                    timeRange: AISubtitleTimeRange(start: 59.2, end: 60.2),
                    text: "Continues into new audio",
                    language: english),
  AISubtitleSegment(id: "new-audio",
                    timeRange: AISubtitleTimeRange(start: 60.2, end: 61.5),
                    text: "New audio",
                    language: english)
], in: AISubtitleTimeRange(start: 58.5, end: 118.5), overlapDuration: 1.5)
expect(overlapPolicySegments.map(\.id) == ["crosses-boundary", "new-audio"],
       "Speech wholly inside a repeated audio overlap should provide context without creating another cue")
let mismatchRoot = tempRoot.appendingPathComponent("possible-language-mismatch", isDirectory: true)
let mismatchStore = AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: mismatchRoot))
let mismatchKey = AISubtitleCacheKey(media: sameLanguageMedia,
                                     transcriberID: .apple,
                                     translatorID: nil,
                                     transcriberModelIdentifier: "possible-language-mismatch-test")
let mismatchExtractor = TestExtractor()
let mismatchScheduler = AISubtitleScheduler(
  extractor: mismatchExtractor,
  transcriber: EmptyTestTranscriber(),
  translator: RejectingTestTranslator(),
  cacheStore: mismatchStore,
  configuration: AISubtitleScheduler.Configuration(
    chunkPlanner: AISubtitleChunkPlanner(chunkDuration: 60, overlapDuration: 0)))
let mismatchPaused = DispatchSemaphore(value: 0)
var mismatchState: AISubtitleTaskState?
mismatchScheduler.start(media: sameLanguageMedia,
                        mediaDuration: 600,
                        cacheKey: mismatchKey,
                        playbackPosition: 0,
                        stateHandler: { state in
                          if state.phase == .failed {
                            mismatchState = state
                            mismatchPaused.signal()
                          }
                        },
                        subtitleFileHandler: { _ in })
expect(mismatchPaused.wait(timeout: .now() + 5) == .success
       && mismatchExtractor.ranges.count == 2
       && mismatchState?.error?.code == "ai_subtitle_possible_language_mismatch"
       && mismatchState?.progress == 0.2,
       "Repeated empty transcription should pause early and preserve resumable progress")
mismatchScheduler.cancel()

let mismatchResumeExtractor = TestExtractor()
let mismatchResumeScheduler = AISubtitleScheduler(
  extractor: mismatchResumeExtractor,
  transcriber: EmptyTestTranscriber(),
  translator: RejectingTestTranslator(),
  cacheStore: mismatchStore,
  configuration: AISubtitleScheduler.Configuration(
    chunkPlanner: AISubtitleChunkPlanner(chunkDuration: 60, overlapDuration: 0)))
let mismatchResumed = DispatchSemaphore(value: 0)
mismatchResumeScheduler.start(media: sameLanguageMedia,
                              mediaDuration: 600,
                              cacheKey: mismatchKey,
                              playbackPosition: 0,
                              stateHandler: { if $0.phase == .completed { mismatchResumed.signal() } },
                              subtitleFileHandler: { _ in })
expect(mismatchResumed.wait(timeout: .now() + 5) == .success
       && mismatchResumeExtractor.ranges.first?.start == 120,
       "Retrying after an empty-opening warning should resume without warning again")
mismatchResumeScheduler.cancel()

let resumedExtractor = TestExtractor()
let resumedScheduler = AISubtitleScheduler(extractor: resumedExtractor,
                                           transcriber: TestTranscriber(),
                                           translator: AISubtitlePassThroughTranslator(providerID: .apple),
                                           cacheStore: schedulerStore)
let resumed = DispatchSemaphore(value: 0)
resumedScheduler.start(media: sameLanguageMedia,
                       mediaDuration: 130,
                       cacheKey: schedulerKey,
                       playbackPosition: 0,
                       stateHandler: { if $0.phase == .completed { resumed.signal() } },
                       subtitleFileHandler: { _ in })
expect(resumed.wait(timeout: .now() + 5) == .success && resumedExtractor.ranges.isEmpty,
       "Scheduler should resume from a complete cache without extracting again")
resumedScheduler.cancel()

let seekRoot = tempRoot.appendingPathComponent("seek", isDirectory: true)
let seekExtractor = ControlledTestExtractor()
let seekScheduler = AISubtitleScheduler(extractor: seekExtractor,
                                        transcriber: TestTranscriber(),
                                        translator: AISubtitlePassThroughTranslator(providerID: .apple),
                                        cacheStore: AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: seekRoot)),
                                        configuration: AISubtitleScheduler.Configuration(
                                          aheadDuration: 300,
                                          refillThreshold: 60,
                                          chunkPlanner: AISubtitleChunkPlanner(chunkDuration: 300,
                                                                                overlapDuration: 0)))
let seekKey = AISubtitleCacheKey(media: sameLanguageMedia,
                                 transcriberID: .apple,
                                 translatorID: nil,
                                 transcriberModelIdentifier: "seek-test")
seekScheduler.start(media: sameLanguageMedia,
                    mediaDuration: 1_000,
                    cacheKey: seekKey,
                    playbackPosition: 0,
                    stateHandler: { _ in },
                    subtitleFileHandler: { _ in })
guard let firstSeekExtraction = seekExtractor.next() else {
  expect(false, "Seek independence test should start extracting from the beginning")
  fatalError()
}
expect(firstSeekExtraction.timeRange.start == 0,
       "Full-video generation should always begin at the start of the media")
try FileManager.default.createDirectory(at: firstSeekExtraction.outputURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try Data([0, 1, 2]).write(to: firstSeekExtraction.outputURL)
seekScheduler.updatePlaybackPosition(600)
firstSeekExtraction.succeed()
guard let postSeekExtraction = seekExtractor.next() else {
  expect(false, "Generation should continue after a playback seek")
  fatalError()
}
expect(postSeekExtraction.timeRange == AISubtitleTimeRange(start: 300, end: 600),
       "Seeking should not reorder or interrupt the sequential full-video generation queue")
seekScheduler.cancel()

let cancelRoot = tempRoot.appendingPathComponent("cancel", isDirectory: true)
let cancelExtractor = ControlledTestExtractor()
let cancelScheduler = AISubtitleScheduler(extractor: cancelExtractor,
                                          transcriber: TestTranscriber(),
                                          translator: AISubtitlePassThroughTranslator(providerID: .apple),
                                          cacheStore: AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: cancelRoot)))
let canceledState = DispatchSemaphore(value: 0)
var canceledSubtitleWasPublished = false
cancelScheduler.start(media: sameLanguageMedia,
                      mediaDuration: 300,
                      cacheKey: AISubtitleCacheKey(media: sameLanguageMedia,
                                                   transcriberID: .apple,
                                                   translatorID: nil,
                                                   transcriberModelIdentifier: "cancel-test"),
                      playbackPosition: 0,
                      stateHandler: { if $0.phase == .canceled { canceledState.signal() } },
                      subtitleFileHandler: { _ in canceledSubtitleWasPublished = true })
guard let canceledExtraction = cancelExtractor.next() else {
  expect(false, "Cancel test should have an active extraction")
  fatalError()
}
try FileManager.default.createDirectory(at: canceledExtraction.outputURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try Data([0, 1, 2]).write(to: canceledExtraction.outputURL)
cancelScheduler.cancel()
expect(canceledState.wait(timeout: .now() + 2) == .success,
       "Cancel should transition the scheduler before stale extraction completion")
canceledExtraction.succeed()
expectEventually({ !FileManager.default.fileExists(atPath: canceledExtraction.outputURL.path) },
                 "A chunk completing after cancel should be deleted")
Thread.sleep(forTimeInterval: 0.05)
expect(!canceledSubtitleWasPublished,
       "A stale completion after cancel must not publish a subtitle file")

let failureRoot = tempRoot.appendingPathComponent("failure-recovery", isDirectory: true)
let failureKey = AISubtitleCacheKey(media: sameLanguageMedia,
                                    transcriberID: .apple,
                                    translatorID: nil,
                                    transcriberModelIdentifier: "failure-recovery-test")
let failingExtractor = ControlledTestExtractor()
let failingScheduler = AISubtitleScheduler(extractor: failingExtractor,
                                           transcriber: TestTranscriber(),
                                           translator: AISubtitlePassThroughTranslator(providerID: .apple),
                                           cacheStore: AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: failureRoot)))
let failedState = DispatchSemaphore(value: 0)
failingScheduler.start(media: sameLanguageMedia,
                       mediaDuration: 60,
                       cacheKey: failureKey,
                       playbackPosition: 0,
                       stateHandler: { if $0.phase == .failed { failedState.signal() } },
                       subtitleFileHandler: { _ in })
guard let failedExtraction = failingExtractor.next() else {
  expect(false, "Failure test should start extraction")
  fatalError()
}
failedExtraction.fail()
expect(failedState.wait(timeout: .now() + 2) == .success,
       "Extraction failure should enter a recoverable failed state")
failingScheduler.cancel()
let recoveryExtractor = TestExtractor()
let recoveryScheduler = AISubtitleScheduler(extractor: recoveryExtractor,
                                            transcriber: TestTranscriber(),
                                            translator: AISubtitlePassThroughTranslator(providerID: .apple),
                                            cacheStore: AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: failureRoot)))
let recoveredState = DispatchSemaphore(value: 0)
recoveryScheduler.start(media: sameLanguageMedia,
                        mediaDuration: 60,
                        cacheKey: failureKey,
                        playbackPosition: 0,
                        stateHandler: { if $0.phase == .completed { recoveredState.signal() } },
                        subtitleFileHandler: { _ in })
expect(recoveredState.wait(timeout: .now() + 2) == .success && recoveryExtractor.ranges.count == 1,
       "Starting a new job after failure should recover and fill the missing range")
recoveryScheduler.cancel()

let longVideoRoot = tempRoot.appendingPathComponent("long-video", isDirectory: true)
let longVideoExtractor = TestExtractor()
let longVideoScheduler = AISubtitleScheduler(
  extractor: longVideoExtractor,
  transcriber: TestTranscriber(),
  translator: AISubtitlePassThroughTranslator(providerID: .apple),
  cacheStore: AISubtitleCacheStore(layout: AISubtitleCacheLayout(rootURL: longVideoRoot)),
  configuration: AISubtitleScheduler.Configuration(
    aheadDuration: 300,
    refillThreshold: 60,
    chunkPlanner: AISubtitleChunkPlanner(chunkDuration: 300, overlapDuration: 0))
)
let longVideoCompleted = DispatchSemaphore(value: 0)
longVideoScheduler.start(media: sameLanguageMedia,
                         mediaDuration: 7_200,
                         cacheKey: AISubtitleCacheKey(media: sameLanguageMedia,
                                                      transcriberID: .apple,
                                                      translatorID: nil,
                                                      transcriberModelIdentifier: "long-video-test"),
                         playbackPosition: 0,
                         stateHandler: { if $0.phase == .completed { longVideoCompleted.signal() } },
                         subtitleFileHandler: { _ in })
expect(longVideoCompleted.wait(timeout: .now() + 10) == .success,
       "A long video should finish its full generation queue")
expect(longVideoExtractor.ranges.count == 24 &&
       longVideoExtractor.ranges.last?.end == 7_200,
       "A two-hour video should process every chunk through the end of the media")
longVideoScheduler.cancel()

let largeTranscript = (0..<10_000).map { index in
  let start = Double(index) * 2
  return AISubtitleSegment(id: "large-\(index)",
                           timeRange: AISubtitleTimeRange(start: start, end: start + 1),
                           text: "subtitle \(index)",
                           language: english)
}
let largeTimelineStarted = Date()
let largeCues = AISubtitleTimelineAssembler().assemble(largeTranscript, targetLanguage: english)
let largeVTT = AISubtitleFileWriter().string(for: largeCues, format: .webVTT)
expect(largeCues.count == 10_000 && largeVTT.contains("subtitle 9999"),
       "Large subtitle timelines should preserve every non-overlapping cue")
expect(Date().timeIntervalSince(largeTimelineStarted) < 5,
       "Assembling and serializing 10,000 cues should remain bounded")

let deniedTransport = TestHTTPTransport()
let deniedTranscriber = OpenAIAISubtitleTranscriber(apiKeyProvider: TestAPIKeys(values: [.openAI: "test-key"]),
                                                    consentChecker: TestConsent(providers: []),
                                                    transport: deniedTransport)
expect(deniedTranscriber.capability(for: request).status == .needsAuthorization,
       "Cloud transcription should require explicit consent")
let deniedAudioURL = tempRoot.appendingPathComponent("denied.wav")
try Data([0, 1, 2]).write(to: deniedAudioURL)
if #available(macOS 26.0, *) {
  let appleTranscriber = AppleAISubtitleTranscriber()
  let unsupportedSpeechRequest = AISubtitleProviderRequest(
    sourceLanguage: AISubtitleLanguage("zz-ZZ"),
    targetLanguage: english,
    media: media
  )
  let unsupportedSpeechProbeSignal = DispatchSemaphore(value: 0)
  var unsupportedSpeechCapability: AISubtitleProviderCapability?
  Task {
    unsupportedSpeechCapability = await appleTranscriber.probe(language: AISubtitleLanguage("zz-ZZ"))
    unsupportedSpeechProbeSignal.signal()
  }
  expect(waitWhileRunningMainLoop(unsupportedSpeechProbeSignal, timeout: 5)
         && unsupportedSpeechCapability?.status == .unavailable,
         "Apple Speech should report an unsupported spoken language without requesting assets")
  let unsupportedSpeechSignal = DispatchSemaphore(value: 0)
  var unsupportedSpeechError: AISubtitleError?
  appleTranscriber.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                                   timeRange: AISubtitleTimeRange(start: 0, end: 1),
                                                   format: .wav16kMono),
                               request: unsupportedSpeechRequest) {
    if case .failure(let error) = $0 { unsupportedSpeechError = error }
    unsupportedSpeechSignal.signal()
  }
  expect(waitWhileRunningMainLoop(unsupportedSpeechSignal, timeout: 5)
         && unsupportedSpeechError?.code == "apple_speech_language_unsupported"
         && unsupportedSpeechError?.recoverable == false,
         "Apple Speech should fail unsupported languages before reading audio")

  let appleTranslator = AppleAISubtitleTranslator()
  let unsupportedTranslationProbeSignal = DispatchSemaphore(value: 0)
  var unsupportedTranslationCapability: AISubtitleProviderCapability?
  Task {
    unsupportedTranslationCapability = await appleTranslator.probe(
      sourceLanguage: AISubtitleLanguage("zz-ZZ"),
      targetLanguage: english
    )
    unsupportedTranslationProbeSignal.signal()
  }
  expect(waitWhileRunningMainLoop(unsupportedTranslationProbeSignal, timeout: 15),
         "Apple Translation language availability should finish within 15 seconds")
  expect(unsupportedTranslationCapability?.status == .unavailable,
         "Apple Translation should report an unsupported language pair without requesting assets; got \(String(describing: unsupportedTranslationCapability?.status))")
  let unsupportedTranslationSignal = DispatchSemaphore(value: 0)
  var unsupportedTranslationError: AISubtitleError?
  appleTranslator.translate(transcript, request: unsupportedSpeechRequest) {
    if case .failure(let error) = $0 { unsupportedTranslationError = error }
    unsupportedTranslationSignal.signal()
  }
  expect(waitWhileRunningMainLoop(unsupportedTranslationSignal, timeout: 15)
         && unsupportedTranslationError?.code == "apple_translation_language_unsupported"
         && unsupportedTranslationError?.recoverable == false,
         "Apple Translation should distinguish unsupported pairs from downloadable assets")
}
var deniedError: AISubtitleError?
deniedTranscriber.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                                  timeRange: AISubtitleTimeRange(start: 0, end: 1),
                                                  format: .wav16kMono),
                              request: request) {
  if case .failure(let error) = $0 { deniedError = error }
}
expect(deniedError?.code == "openai_cloud_consent_required" && deniedTransport.requests.isEmpty,
       "Denied cloud work should fail before reading or uploading audio")
let deniedFallbackFactory = AISubtitleCloudProviderFactory(
  openAIAPIKeyProvider: TestAPIKeys(values: [.openAI: "test-key"]),
  consentChecker: TestConsent(providers: []),
  transport: deniedTransport
)
if case .failure(let fallbackError) = deniedFallbackFactory.makePair(providerID: .openAI,
                                                                     request: request) {
  expect(fallbackError.code == "openAI_transcriber_needsAuthorization" && deniedTransport.requests.isEmpty,
         "Automatic cloud fallback should remain blocked without explicit upload consent")
} else {
  expect(false, "A cloud fallback without upload consent must not be created")
}
let deniedAliyunTransport = TestHTTPTransport()
let deniedAliyunCredentials = TestAliyunCredentials(value: AISubtitleAliyunCredentials(
  dashScopeAPIKey: "dashscope-test-key",
  machineTranslationAccessKeyID: "id",
  machineTranslationAccessKeySecret: "secret"
))
let deniedAliyunTranscriber = AliyunAISubtitleTranscriber(
  credentialProvider: deniedAliyunCredentials,
  consentChecker: TestConsent(providers: []),
  publisher: UnavailableAISubtitleAliyunAudioPublisher(),
  transport: deniedAliyunTransport
)
expect(deniedAliyunTranscriber.capability(for: request).status == .needsAuthorization,
       "Aliyun transcription should require explicit consent before checking upload configuration")
var deniedAliyunTranscriptionError: AISubtitleError?
deniedAliyunTranscriber.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                                        timeRange: AISubtitleTimeRange(start: 0, end: 1),
                                                        format: .wav16kMono),
                                    request: request) {
  if case .failure(let error) = $0 { deniedAliyunTranscriptionError = error }
}
expect(deniedAliyunTranscriptionError?.code == "aliyun_cloud_consent_required"
       && deniedAliyunTransport.requests.isEmpty,
       "Denied Aliyun transcription should not publish audio or send HTTP requests")
let deniedAliyunTranslator = AliyunAISubtitleTranslator(
  credentialProvider: deniedAliyunCredentials,
  consentChecker: TestConsent(providers: []),
  transport: deniedAliyunTransport
)
expect(deniedAliyunTranslator.capability(for: request).status == .needsAuthorization,
       "Aliyun translation should require explicit consent before checking credentials")
var deniedAliyunTranslationError: AISubtitleError?
deniedAliyunTranslator.translate(transcript, request: request) {
  if case .failure(let error) = $0 { deniedAliyunTranslationError = error }
}
expect(deniedAliyunTranslationError?.code == "aliyun_cloud_consent_required"
       && deniedAliyunTransport.requests.isEmpty,
       "Denied Aliyun translation should not send subtitle text over HTTP")
let deniedAliyunFactory = AISubtitleCloudProviderFactory(
  aliyunCredentialProvider: deniedAliyunCredentials,
  consentChecker: TestConsent(providers: []),
  aliyunAudioPublisher: UnavailableAISubtitleAliyunAudioPublisher(),
  transport: deniedAliyunTransport
)
if case .failure(let fallbackError) = deniedAliyunFactory.makePair(providerID: .aliyun,
                                                                   request: request) {
  expect(fallbackError.code == "aliyun_transcriber_needsAuthorization"
         && deniedAliyunTransport.requests.isEmpty,
         "Automatic Aliyun fallback should remain blocked without explicit upload consent")
} else {
  expect(false, "An Aliyun fallback without upload consent must not be created")
}
let suspendedTransport = SuspendedTestHTTPTransport()
let cancelableOpenAI = OpenAIAISubtitleTranscriber(
  apiKeyProvider: TestAPIKeys(values: [.openAI: "test-key"]),
  consentChecker: TestConsent(providers: [.openAI]),
  transport: suspendedTransport
)
cancelableOpenAI.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                                 timeRange: AISubtitleTimeRange(start: 0, end: 1),
                                                 format: .wav16kMono),
                             request: request) { _ in }
cancelableOpenAI.cancelAll()
expect(suspendedTransport.tasks.count == 1 && suspendedTransport.tasks[0].isCanceled,
       "Canceling a cloud provider should cancel an in-flight HTTP task")

let failingSessionConfiguration = URLSessionConfiguration.ephemeral
failingSessionConfiguration.protocolClasses = [FailingTestURLProtocol.self]
let failingURLSessionTransport = URLSessionAISubtitleHTTPTransport(
  session: URLSession(configuration: failingSessionConfiguration)
)
let networkFailureSignal = DispatchSemaphore(value: 0)
var mappedNetworkError: AISubtitleError?
failingURLSessionTransport.send(URLRequest(url: URL(string: "https://network-failure.test")!)) {
  if case .failure(let error) = $0 { mappedNetworkError = error }
  networkFailureSignal.signal()
}
expect(networkFailureSignal.wait(timeout: .now() + 2) == .success
       && mappedNetworkError?.code == "cloud_network_failed"
       && mappedNetworkError?.recoverable == true,
       "URLSession network failures should map to a recoverable cloud error")

let openAINetworkTransport = TestHTTPTransport { _ in
  .failure(AISubtitleError(code: "cloud_network_failed",
                           message: "The network connection is offline."))
}
let openAINetworkTranscriber = OpenAIAISubtitleTranscriber(
  apiKeyProvider: TestAPIKeys(values: [.openAI: "test-key"]),
  consentChecker: TestConsent(providers: [.openAI]),
  transport: openAINetworkTransport
)
var openAITranscriptionNetworkError: AISubtitleError?
openAINetworkTranscriber.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                                         timeRange: AISubtitleTimeRange(start: 0, end: 1),
                                                         format: .wav16kMono),
                                     request: request) {
  if case .failure(let error) = $0 { openAITranscriptionNetworkError = error }
}
expect(openAITranscriptionNetworkError?.code == "cloud_network_failed"
       && openAINetworkTransport.requests.count == 1,
       "OpenAI transcription should surface a recoverable network failure")
let openAINetworkTranslator = OpenAIAISubtitleTranslator(
  apiKeyProvider: TestAPIKeys(values: [.openAI: "test-key"]),
  consentChecker: TestConsent(providers: [.openAI]),
  transport: openAINetworkTransport
)
var openAITranslationNetworkError: AISubtitleError?
openAINetworkTranslator.translate(transcript, request: request) {
  if case .failure(let error) = $0 { openAITranslationNetworkError = error }
}
expect(openAITranslationNetworkError?.code == "cloud_network_failed"
       && openAINetworkTransport.requests.count == 2,
       "OpenAI translation should surface a recoverable network failure")
openAINetworkTranscriber.cancelAll()
openAINetworkTranslator.cancelAll()
expect(openAINetworkTransport.tasks.allSatisfy({ !$0.isCanceled }),
       "Completed OpenAI network failures should be released from cancellation tracking")

let signer = AISubtitleAliyunROASigner(date: Date(timeIntervalSince1970: 0), nonce: "fixed-nonce")
let signedRequest = signer.signedRequest(
  endpoint: URL(string: "https://mt.cn-hangzhou.aliyuncs.com/api/translate/web/general")!,
  body: Data("hello".utf8),
  credentials: AISubtitleAliyunMachineTranslationCredentials(accessKeyID: "id", accessKeySecret: "secret")
)
expect(signedRequest.value(forHTTPHeaderField: "Authorization") == "acs id:5TJqrdZZTaIdTQMEk+RiX+Njy80=",
       "Aliyun request signing should match the fixed vector")

let aliyunCredentials = TestAliyunCredentials(value: AISubtitleAliyunCredentials(
  dashScopeAPIKey: "dashscope-test-key",
  machineTranslationAccessKeyID: "id",
  machineTranslationAccessKeySecret: "secret"
))
let aliyunUploadNetworkTransport = TestHTTPTransport { _ in
  .failure(AISubtitleError(code: "cloud_network_failed",
                           message: "The network connection is offline."))
}
let aliyunUploadNetworkPublisher = DashScopeTemporaryAISubtitleAliyunAudioPublisher(
  credentialProvider: aliyunCredentials,
  transport: aliyunUploadNetworkTransport
)
var aliyunUploadNetworkError: AISubtitleError?
aliyunUploadNetworkPublisher.publish(AISubtitleAudioChunk(url: deniedAudioURL,
                                                          timeRange: AISubtitleTimeRange(start: 0, end: 1),
                                                          format: .wav16kMono)) {
  if case .failure(let error) = $0 { aliyunUploadNetworkError = error }
}
expect(aliyunUploadNetworkError?.code == "cloud_network_failed"
       && aliyunUploadNetworkTransport.requests.count == 1,
       "Aliyun temporary publishing should surface a network failure before audio upload")
aliyunUploadNetworkPublisher.cancelAll()
expect(aliyunUploadNetworkTransport.tasks.allSatisfy({ !$0.isCanceled }),
       "A completed Aliyun upload credential failure should be released from cancellation tracking")
let aliyunNetworkTransport = TestHTTPTransport { _ in
  .failure(AISubtitleError(code: "cloud_network_failed",
                           message: "The network connection is offline."))
}
let aliyunNetworkPublisher = TestAliyunAudioPublisher()
let aliyunNetworkTranscriber = AliyunAISubtitleTranscriber(
  credentialProvider: aliyunCredentials,
  consentChecker: TestConsent(providers: [.aliyun]),
  publisher: aliyunNetworkPublisher,
  transport: aliyunNetworkTransport,
  pollInterval: 0,
  delay: { _, work in work() }
)
var aliyunTranscriptionNetworkError: AISubtitleError?
aliyunNetworkTranscriber.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                                         timeRange: AISubtitleTimeRange(start: 0, end: 1),
                                                         format: .wav16kMono),
                                     request: request) {
  if case .failure(let error) = $0 { aliyunTranscriptionNetworkError = error }
}
expect(aliyunTranscriptionNetworkError?.code == "cloud_network_failed"
       && aliyunNetworkPublisher.publishCount == 1
       && aliyunNetworkPublisher.revokedURLs == [aliyunNetworkPublisher.publishedURL]
       && aliyunNetworkTransport.requests.count == 1,
       "Aliyun submission failure should surface the network error and revoke published audio")
let aliyunNetworkTranslator = AliyunAISubtitleTranslator(
  credentialProvider: aliyunCredentials,
  consentChecker: TestConsent(providers: [.aliyun]),
  transport: aliyunNetworkTransport
)
var aliyunTranslationNetworkError: AISubtitleError?
aliyunNetworkTranslator.translate(transcript, request: request) {
  if case .failure(let error) = $0 { aliyunTranslationNetworkError = error }
}
expect(aliyunTranslationNetworkError?.code == "cloud_network_failed"
       && aliyunNetworkTransport.requests.count == 2,
       "Aliyun translation should surface a recoverable network failure")
aliyunNetworkTranscriber.cancelAll()
aliyunNetworkTranslator.cancelAll()
expect(aliyunNetworkTransport.tasks.allSatisfy({ !$0.isCanceled }),
       "Completed Aliyun network failures should be released from cancellation tracking")
let uploadCredential = """
{"data":{"policy":"policy","signature":"signature","upload_dir":"dashscope-instant/test/path","upload_host":"https://upload.example","oss_access_key_id":"temporary-id","x_oss_object_acl":"private","x_oss_forbid_overwrite":"true"}}
""".data(using: .utf8)!
let transcriptionResult = """
{"transcripts":[{"sentences":[{"begin_time":500,"end_time":2000,"text":" aliyun hello ","sentence_id":1}]}]}
""".data(using: .utf8)!
let aliyunTransport = TestHTTPTransport { request in
  switch request.url!.host {
  case "dashscope.aliyuncs.com" where request.url!.path == "/api/v1/uploads":
    return TestHTTPTransport.response(for: request, data: uploadCredential)
  case "upload.example":
    return TestHTTPTransport.response(for: request)
  case "dashscope.aliyuncs.com" where request.url!.path.contains("/tasks/"):
    return TestHTTPTransport.response(for: request,
                                      data: "{\"output\":{\"task_status\":\"SUCCEEDED\",\"results\":[{\"subtask_status\":\"SUCCEEDED\",\"transcription_url\":\"https://result.example/result.json\"}]}}".data(using: .utf8)!)
  case "dashscope.aliyuncs.com":
    return TestHTTPTransport.response(for: request,
                                      data: "{\"output\":{\"task_id\":\"task-1\"}}".data(using: .utf8)!)
  case "result.example":
    return TestHTTPTransport.response(for: request, data: transcriptionResult)
  default:
    return .failure(AISubtitleError(code: "unexpected_request", message: request.url!.absoluteString))
  }
}
let temporaryPublisher = DashScopeTemporaryAISubtitleAliyunAudioPublisher(
  credentialProvider: aliyunCredentials,
  transport: aliyunTransport
)
let aliyunTranscriber = AliyunAISubtitleTranscriber(
  credentialProvider: aliyunCredentials,
  consentChecker: TestConsent(providers: [.aliyun]),
  publisher: temporaryPublisher,
  transport: aliyunTransport,
  pollInterval: 0,
  delay: { _, work in work() }
)
var aliyunSegments: [AISubtitleSegment] = []
aliyunTranscriber.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                                  timeRange: AISubtitleTimeRange(start: 100, end: 160),
                                                  format: .wav16kMono),
                              request: request) {
  if case .success(let segments) = $0 { aliyunSegments = segments }
}
let aliyunSubmitRequest = aliyunTransport.requests.first {
  $0.url?.path.contains("/audio/asr/transcription") == true
}
let aliyunUploadBody = aliyunTransport.requests.first { $0.url?.host == "upload.example" }?.httpBody
expect(aliyunSegments.first?.timeRange == AISubtitleTimeRange(start: 100.5, end: 102) &&
       aliyunSubmitRequest?.value(forHTTPHeaderField: "X-DashScope-OssResourceResolve") == "enable",
       "Aliyun temporary upload should feed an OSS URL into Paraformer")
expect(aliyunUploadBody.flatMap { String(data: $0, encoding: .utf8) }?.contains("name=\"file\"") == true,
       "Aliyun temporary upload should send the WAV as multipart form data")
aliyunTranscriber.cancelAll()
expect(aliyunTransport.tasks.allSatisfy({ !$0.isCanceled }),
       "Completed Aliyun HTTP tasks should be released instead of retained for later cancellation")

let modelSource = tempRoot.appendingPathComponent("ggml-test.bin")
let modelDirectory = tempRoot.appendingPathComponent("models", isDirectory: true)
try Data(repeating: 0, count: 1_048_576).write(to: modelSource)
let modelManager = AISubtitleWhisperModelManager(modelsDirectoryURL: modelDirectory)
let model = try modelManager.importModel(from: modelSource,
                                         expectedSHA256: "30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58")
let secondModelSource = tempRoot.appendingPathComponent("ggml-test-second.bin")
try Data(repeating: 1, count: 1_048_576).write(to: secondModelSource)
let secondModel = try modelManager.importModel(from: secondModelSource)
let modelDefaultsSuite = "ai-subtitle-model-test-\(UUID().uuidString)"
let modelDefaults = UserDefaults(suiteName: modelDefaultsSuite)!
defer { modelDefaults.removePersistentDomain(forName: modelDefaultsSuite) }
try modelManager.select(secondModel, userDefaults: modelDefaults)
expect(modelManager.selectedModel(userDefaults: modelDefaults)?.url.standardizedFileURL == secondModel.url.standardizedFileURL,
       "The selected whisper.cpp model should persist independently of inventory order")
let whisperJSON = """
{"result":{"language":"en"},"transcription":[{"offsets":{"from":500,"to":2000},"text":" local hello "}]}
""".data(using: .utf8)!
let whisperRunner = TestWhisperRunner(outputJSON: whisperJSON)
let missingModelWhisper = WhisperCppAISubtitleTranscriber(
  installation: AISubtitleWhisperInstallation(executableURL: tempRoot.appendingPathComponent("whisper-cli"),
                                               selectedModel: nil),
  runner: whisperRunner
)
expect(missingModelWhisper.capability(for: request).status == .needsDownload,
       "whisper.cpp should report a missing model before a local process is launched")
var missingModelError: AISubtitleError?
missingModelWhisper.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                                    timeRange: AISubtitleTimeRange(start: 0, end: 1),
                                                    format: .wav16kMono),
                                request: request) {
  if case .failure(let error) = $0 { missingModelError = error }
}
expect(missingModelError?.code == "whisper_assets_required" && whisperRunner.arguments.isEmpty,
       "whisper.cpp should fail without launching a process when no model is selected")
let whisper = WhisperCppAISubtitleTranscriber(
  installation: AISubtitleWhisperInstallation(executableURL: tempRoot.appendingPathComponent("whisper-cli"),
                                               selectedModel: model),
  runner: whisperRunner
)
var whisperSegments: [AISubtitleSegment] = []
whisper.transcribe(AISubtitleAudioChunk(url: deniedAudioURL,
                                       timeRange: AISubtitleTimeRange(start: 100, end: 160),
                                       format: .wav16kMono),
                   request: request) {
  if case .success(let segments) = $0 { whisperSegments = segments }
}
expect(whisperSegments.first?.timeRange == AISubtitleTimeRange(start: 100.5, end: 102) &&
       whisperRunner.arguments.contains("-oj"),
       "whisper.cpp JSON offsets should map to the media timeline")
whisper.cancelAll()
expect(whisperRunner.cancelCount == 1, "whisper.cpp cancellation should reach the process runner")
let realProcessRunner = AISubtitleWhisperProcessRunner(
  queue: DispatchQueue(label: "AISubtitleWhisperProcessCancellationTest")
)
let processCanceled = DispatchSemaphore(value: 0)
realProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"),
                      arguments: ["10"]) { _ in
  processCanceled.signal()
}
Thread.sleep(forTimeInterval: 0.05)
realProcessRunner.cancelAll()
expect(processCanceled.wait(timeout: .now() + 2) == .success,
       "Canceling whisper.cpp should terminate a real child process promptly")
try modelManager.remove(secondModel)
try modelManager.remove(model)
expect(modelManager.installedModels().isEmpty,
       "Managed whisper.cpp models should be removable")

print("AI subtitle self-tests passed")
