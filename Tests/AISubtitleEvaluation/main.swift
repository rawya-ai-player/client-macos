import Foundation

private enum EvaluationError: Error, CustomStringConvertible {
  case usage
  case resource(String)
  case generation(String)

  var description: String {
    switch self {
    case .usage:
      return "Usage:\n  ai-subtitle-eval probe <source> <target>\n  ai-subtitle-eval prepare <source> <target>\n  ai-subtitle-eval translate <source> <target> <text>\n  ai-subtitle-eval translate-transcript <transcript.json> <source> <target> <output-dir> <sample-name>\n  ai-subtitle-eval render-pair <transcript.json> <translated-cues.json> <source> <target> <output-dir> <sample-name>\n  ai-subtitle-eval translate-srt <source.srt> <source> <target> <output-dir> <sample-name>\n  ai-subtitle-eval generate <input> <source> <target> <output-dir> [duration-seconds]\n  ai-subtitle-eval generate-dictation <input> <source> <target> <output-dir> [duration-seconds]"
    case .resource(let message), .generation(let message):
      return message
    }
  }
}

private final class GenerationResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var artifacts: AISubtitleCacheArtifacts?
  private var error: AISubtitleError?
  private var lastProgress = -1
  private var finished = false

  func setArtifacts(_ artifacts: AISubtitleCacheArtifacts) {
    lock.lock()
    self.artifacts = artifacts
    lock.unlock()
  }

  func update(_ state: AISubtitleTaskState) -> (shouldPrint: Bool, didFinish: Bool) {
    lock.lock()
    defer { lock.unlock() }
    let percent = Int(((state.progress ?? 0) * 100).rounded())
    let shouldPrint = percent >= lastProgress + 5 || state.phase == .completed || state.phase == .failed
    if shouldPrint { lastProgress = percent }
    let terminal = state.phase == .failed || state.phase == .completed
    if terminal { error = state.error }
    let didFinish = terminal && !finished
    if didFinish { finished = true }
    return (shouldPrint, didFinish)
  }

  func snapshot() -> (AISubtitleCacheArtifacts?, AISubtitleError?) {
    lock.lock()
    defer { lock.unlock() }
    return (artifacts, error)
  }
}

private func probedDuration(of mediaURL: URL) throws -> Double {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
  process.arguments = [
    "-v", "error",
    "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1",
    mediaURL.path
  ]
  let outputPipe = Pipe()
  let errorPipe = Pipe()
  process.standardOutput = outputPipe
  process.standardError = errorPipe
  try process.run()
  process.waitUntilExit()
  let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines)
  guard process.terminationStatus == 0, let output, let duration = Double(output), duration > 0 else {
    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    throw EvaluationError.generation(error?.isEmpty == false ? error! : "ffprobe could not read the media duration.")
  }
  return duration
}

@main
private struct AISubtitleEvaluationMain {
  static func main() async {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      guard let command = arguments.first else { throw EvaluationError.usage }
      switch command {
      case "probe":
        guard arguments.count == 3 else { throw EvaluationError.usage }
        try await probe(sourceCode: arguments[1], targetCode: arguments[2])
      case "prepare":
        guard arguments.count == 3 else { throw EvaluationError.usage }
        try await prepare(sourceCode: arguments[1], targetCode: arguments[2])
      case "translate":
        guard arguments.count == 4 else { throw EvaluationError.usage }
        try await translate(sourceCode: arguments[1], targetCode: arguments[2], text: arguments[3])
      case "translate-transcript":
        guard arguments.count == 6 else { throw EvaluationError.usage }
        try await translateTranscript(transcriptPath: arguments[1],
                                      sourceCode: arguments[2],
                                      targetCode: arguments[3],
                                      outputPath: arguments[4],
                                      sampleName: arguments[5])
      case "render-pair":
        guard arguments.count == 7 else { throw EvaluationError.usage }
        try renderPair(transcriptPath: arguments[1],
                       translatedCuesPath: arguments[2],
                       sourceCode: arguments[3],
                       targetCode: arguments[4],
                       outputPath: arguments[5],
                       sampleName: arguments[6])
      case "translate-srt":
        guard arguments.count == 6 else { throw EvaluationError.usage }
        try await translateSRT(srtPath: arguments[1],
                               sourceCode: arguments[2],
                               targetCode: arguments[3],
                               outputPath: arguments[4],
                               sampleName: arguments[5])
      case "generate":
        guard arguments.count == 5 || arguments.count == 6 else { throw EvaluationError.usage }
        try await generate(inputPath: arguments[1],
                           sourceCode: arguments[2],
                           targetCode: arguments[3],
                           outputPath: arguments[4],
                           durationLimit: arguments.count == 6 ? Double(arguments[5]) : nil)
      case "generate-dictation":
        guard arguments.count == 5 || arguments.count == 6 else { throw EvaluationError.usage }
        try await generate(inputPath: arguments[1],
                           sourceCode: arguments[2],
                           targetCode: arguments[3],
                           outputPath: arguments[4],
                           durationLimit: arguments.count == 6 ? Double(arguments[5]) : nil,
                           usesDictation: true)
      default:
        throw EvaluationError.usage
      }
    } catch {
      fputs("\(error)\n", stderr)
      exit(1)
    }
  }

  @available(macOS 26.0, *)
  private static func probeAvailable(sourceCode: String, targetCode: String) async throws {
    let source = AISubtitleLanguage(sourceCode)
    let target = AISubtitleLanguage(targetCode)
    let speech = await AppleAISubtitleTranscriber().probe(language: source)
    let translation = await AppleAISubtitleTranslator().probe(sourceLanguage: source,
                                                               targetLanguage: target)
    print("speech=\(speech.status.rawValue) \(speech.reason ?? "")")
    print("translation=\(translation.status.rawValue) \(translation.reason ?? "")")
  }

  private static func probe(sourceCode: String, targetCode: String) async throws {
    guard #available(macOS 26.0, *) else {
      throw EvaluationError.resource("Apple local AI requires macOS 26 or later.")
    }
    try await probeAvailable(sourceCode: sourceCode, targetCode: targetCode)
  }

  @available(macOS 26.0, *)
  private static func prepareAvailable(sourceCode: String, targetCode: String) async throws {
    let source = AISubtitleLanguage(sourceCode)
    let target = AISubtitleLanguage(targetCode)
    let transcriber = AppleAISubtitleTranscriber()
    let speech = await transcriber.probe(language: source)
    switch speech.status {
    case .available:
      print("speech=available")
    case .needsDownload:
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        var lastProgress = -1
        transcriber.installAssets(language: source, progressHandler: { progress in
          let percent = Int((progress.fractionCompleted * 100).rounded())
          if percent >= lastProgress + 10 {
            lastProgress = percent
            print("speech-download=\(percent)%")
            fflush(stdout)
          }
        }, completion: { result in
          continuation.resume(with: result.mapError { $0 as Error })
        })
      }
    default:
      throw EvaluationError.resource(speech.reason ?? "Speech resource is unavailable.")
    }
    let refreshedSpeech = await transcriber.probe(language: source)
    guard refreshedSpeech.status == .available else {
      throw EvaluationError.resource(refreshedSpeech.reason ?? "Speech resource did not become available.")
    }
    let translation = await AppleAISubtitleTranslator().probe(sourceLanguage: source,
                                                               targetLanguage: target)
    guard translation.status == .available else {
      throw EvaluationError.resource(translation.reason ?? "Prepare this translation language pair in Rawya Settings.")
    }
    print("ready=\(sourceCode)->\(targetCode)")
  }

  private static func prepare(sourceCode: String, targetCode: String) async throws {
    guard #available(macOS 26.0, *) else {
      throw EvaluationError.resource("Apple local AI requires macOS 26 or later.")
    }
    try await prepareAvailable(sourceCode: sourceCode, targetCode: targetCode)
  }

  @available(macOS 26.0, *)
  private static func translateAvailable(sourceCode: String,
                                         targetCode: String,
                                         text: String) async throws {
    let source = AISubtitleLanguage(sourceCode)
    let target = AISubtitleLanguage(targetCode)
    let media = AISubtitleMediaContext(url: URL(fileURLWithPath: "/tmp/translation-experiment.mov"),
                                       isNetworkResource: false,
                                       sourceLanguage: source,
                                       targetLanguage: target)
    let request = AISubtitleProviderRequest(sourceLanguage: source,
                                            targetLanguage: target,
                                            media: media)
    let segment = AISubtitleSegment(id: "experiment",
                                    timeRange: AISubtitleTimeRange(start: 0, end: 10),
                                    text: text,
                                    language: source)
    let translator = AppleAISubtitleTranslator()
    let cues = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<[AISubtitleCue], Error>) in
      translator.translate([segment], request: request) { result in
        continuation.resume(with: result.mapError { $0 as Error })
      }
    }
    guard let translated = cues.first?.text else {
      throw EvaluationError.generation("Apple Translation returned no text.")
    }
    print(translated)
  }

  private static func translate(sourceCode: String,
                                targetCode: String,
                                text: String) async throws {
    guard #available(macOS 26.0, *) else {
      throw EvaluationError.resource("Apple local AI requires macOS 26 or later.")
    }
    try await translateAvailable(sourceCode: sourceCode, targetCode: targetCode, text: text)
  }

  @available(macOS 26.0, *)
  private static func generateAvailable(inputPath: String,
                                        sourceCode: String,
                                        targetCode: String,
                                        outputPath: String,
                                        durationLimit: Double?,
                                        usesDictation: Bool = false) async throws {
    let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
    let attributes = try FileManager.default.attributesOfItem(atPath: inputURL.path)
    let assetDuration = try probedDuration(of: inputURL)
    let duration = min(assetDuration, durationLimit ?? assetDuration)
    let source = AISubtitleLanguage(sourceCode)
    let target = AISubtitleLanguage(targetCode)
    let transcriber: AISubtitleTranscriber
    if usesDictation {
      transcriber = EvaluationAppleDictationTranscriber()
    } else {
      let appleTranscriber = AppleAISubtitleTranscriber()
      let speech = await appleTranscriber.probe(language: source)
      guard speech.status == .available else {
        throw EvaluationError.resource(speech.reason ?? "Speech resource is unavailable.")
      }
      transcriber = appleTranscriber
    }
    let translationRequired = !source.isEquivalent(to: target)
    let appleTranslator = AppleAISubtitleTranslator()
    if translationRequired {
      let translation = await appleTranslator.probe(sourceLanguage: source, targetLanguage: target)
      guard translation.status == .available else {
        throw EvaluationError.resource(translation.reason ?? "Translation resource is unavailable.")
      }
    }

    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    let cacheRoot = outputURL.appendingPathComponent("cache", isDirectory: true)
    let media = AISubtitleMediaContext(
      url: inputURL,
      isNetworkResource: false,
      fileSize: (attributes[.size] as? NSNumber)?.uint64Value,
      fileModifiedAt: attributes[.modificationDate] as? Date,
      sourceLanguage: source,
      targetLanguage: target)
    let translator: AISubtitleTranslator = translationRequired
      ? appleTranslator
      : AISubtitlePassThroughTranslator(providerID: .apple)
    let key = AISubtitleCacheKey(media: media,
                                 transcriberID: .apple,
                                 translatorID: translationRequired ? .apple : nil,
                                 transcriberModelIdentifier: transcriber.modelIdentifier,
                                 translatorModelIdentifier: translationRequired ? translator.modelIdentifier : nil)
    let layout = AISubtitleCacheLayout(rootURL: cacheRoot)
    if let oldArtifacts = try? layout.artifacts(for: key) {
      try? FileManager.default.removeItem(at: oldArtifacts.directoryURL)
    }
    let scheduler = AISubtitleScheduler(extractor: FFmpegAISubtitleAudioExtractor(),
                                        transcriber: transcriber,
                                        translator: translator,
                                        cacheStore: AISubtitleCacheStore(layout: layout))
    let resultBox = GenerationResultBox()
    await withCheckedContinuation { continuation in
      scheduler.start(media: media,
                      mediaDuration: duration,
                      cacheKey: key,
                      playbackPosition: 0,
                      stateHandler: { state in
        let update = resultBox.update(state)
        if update.shouldPrint {
          let percent = Int(((state.progress ?? 0) * 100).rounded())
          print("[\(state.phase.rawValue)] \(percent)%")
          fflush(stdout)
        }
        if update.didFinish { continuation.resume() }
      }, subtitleFileHandler: { artifacts in
        resultBox.setArtifacts(artifacts)
      })
    }
    let (artifacts, error) = resultBox.snapshot()
    if let error { throw EvaluationError.generation("\(error.code): \(error.message)") }
    guard let artifacts else { throw EvaluationError.generation("Generation completed without artifacts.") }

    let stem = inputURL.deletingPathExtension().lastPathComponent
    let runDirectory = outputURL.appendingPathComponent("\(stem).\(sourceCode)-\(targetCode)", isDirectory: true)
    try? FileManager.default.removeItem(at: runDirectory)
    try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
    try copy(artifacts.originalSRTURL, to: runDirectory.appendingPathComponent("original.\(sourceCode).srt"))
    try copy(artifacts.translatedSRTURL, to: runDirectory.appendingPathComponent("translated.\(targetCode).srt"))
    try copy(artifacts.transcriptURL, to: runDirectory.appendingPathComponent("transcript.json"))
    try copy(artifacts.translatedCuesURL, to: runDirectory.appendingPathComponent("translated-cues.json"))
    print(runDirectory.path)
  }

  private static func generate(inputPath: String,
                               sourceCode: String,
                               targetCode: String,
                               outputPath: String,
                               durationLimit: Double?,
                               usesDictation: Bool = false) async throws {
    guard #available(macOS 26.0, *) else {
      throw EvaluationError.resource("Apple local AI requires macOS 26 or later.")
    }
    try await generateAvailable(inputPath: inputPath,
                                sourceCode: sourceCode,
                                targetCode: targetCode,
                                outputPath: outputPath,
                                durationLimit: durationLimit,
                                usesDictation: usesDictation)
  }

  @available(macOS 26.0, *)
  private static func translateTranscriptAvailable(transcriptPath: String,
                                                   sourceCode: String,
                                                   targetCode: String,
                                                   outputPath: String,
                                                   sampleName: String) async throws {
    let transcriptURL = URL(fileURLWithPath: transcriptPath).standardizedFileURL
    let decodedTranscript = try JSONDecoder().decode(
      [AISubtitleSegment].self,
      from: Data(contentsOf: transcriptURL))
    let source = AISubtitleLanguage(sourceCode)
    let transcript = AISubtitleForeignScriptNoiseFilter().filter(decodedTranscript, language: source)
    try await translateSegmentsAvailable(transcript,
                                         sourceCode: sourceCode,
                                         targetCode: targetCode,
                                         outputPath: outputPath,
                                         sampleName: sampleName,
                                         contextURL: transcriptURL)
  }

  @available(macOS 26.0, *)
  private static func translateSegmentsAvailable(_ transcript: [AISubtitleSegment],
                                                 sourceCode: String,
                                                 targetCode: String,
                                                 outputPath: String,
                                                 sampleName: String,
                                                 contextURL: URL) async throws {
    let source = AISubtitleLanguage(sourceCode)
    let target = AISubtitleLanguage(targetCode)
    guard !transcript.isEmpty else {
      throw EvaluationError.generation("The reusable transcript is empty.")
    }

    let translator = AppleAISubtitleTranslator()
    let availability = await translator.probe(sourceLanguage: source, targetLanguage: target)
    guard availability.status == .available else {
      throw EvaluationError.resource(availability.reason ?? "Translation resource is unavailable.")
    }
    let media = AISubtitleMediaContext(
      url: contextURL,
      isNetworkResource: false,
      sourceLanguage: source,
      targetLanguage: target)
    let request = AISubtitleProviderRequest(sourceLanguage: source,
                                            targetLanguage: target,
                                            media: media)
    let translatedCues = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<[AISubtitleCue], Error>) in
      translator.translate(transcript, request: request) { result in
        continuation.resume(with: result.mapError { $0 as Error })
      }
    }
    let timeline = AISubtitlePairedTimelineAssembler().assemble(
      transcript: transcript,
      translatedCues: translatedCues,
      sourceLanguage: source,
      targetLanguage: target)
    try writePair(timeline: timeline,
                  semanticTranscript: transcript,
                  semanticTranslatedCues: translatedCues,
                  sourceCode: sourceCode,
                  targetCode: targetCode,
                  outputPath: outputPath,
                  sampleName: sampleName)
  }

  private static func renderPair(transcriptPath: String,
                                 translatedCuesPath: String,
                                 sourceCode: String,
                                 targetCode: String,
                                 outputPath: String,
                                 sampleName: String) throws {
    let decoder = JSONDecoder()
    let source = AISubtitleLanguage(sourceCode)
    let target = AISubtitleLanguage(targetCode)
    let transcript = AISubtitleForeignScriptNoiseFilter().filter(
      try decoder.decode([AISubtitleSegment].self,
                         from: Data(contentsOf: URL(fileURLWithPath: transcriptPath))),
      language: source)
    let translatedCues = try decoder.decode(
      [AISubtitleCue].self,
      from: Data(contentsOf: URL(fileURLWithPath: translatedCuesPath)))
    let timeline = AISubtitlePairedTimelineAssembler().assemble(
      transcript: transcript,
      translatedCues: translatedCues,
      sourceLanguage: source,
      targetLanguage: target)
    try writePair(timeline: timeline,
                  semanticTranscript: transcript,
                  semanticTranslatedCues: translatedCues,
                  sourceCode: sourceCode,
                  targetCode: targetCode,
                  outputPath: outputPath,
                  sampleName: sampleName)
  }

  private static func writePair(timeline: AISubtitlePairedTimeline,
                                semanticTranscript: [AISubtitleSegment],
                                semanticTranslatedCues: [AISubtitleCue],
                                sourceCode: String,
                                targetCode: String,
                                outputPath: String,
                                sampleName: String) throws {
    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
    let runDirectory = outputURL.appendingPathComponent(
      "\(sampleName).\(sourceCode)-\(targetCode)",
      isDirectory: true)
    try? FileManager.default.removeItem(at: runDirectory)
    try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
    let writer = AISubtitleFileWriter()
    try writer.string(for: timeline.originalCues, format: .srt).write(
      to: runDirectory.appendingPathComponent("original.\(sourceCode).srt"),
      atomically: true,
      encoding: .utf8)
    try writer.string(for: timeline.translatedCues, format: .srt).write(
      to: runDirectory.appendingPathComponent("translated.\(targetCode).srt"),
      atomically: true,
      encoding: .utf8)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(semanticTranscript).write(
      to: runDirectory.appendingPathComponent("transcript.json"),
      options: .atomic)
    try encoder.encode(semanticTranslatedCues).write(
      to: runDirectory.appendingPathComponent("translated-cues.json"),
      options: .atomic)
    print(runDirectory.path)
  }

  private static func parsedSRT(at url: URL,
                                language: AISubtitleLanguage) throws -> [AISubtitleSegment] {
    func seconds(_ timestamp: String) -> Double? {
      let parts = timestamp.replacingOccurrences(of: ",", with: ".").split(separator: ":")
      guard parts.count == 3,
            let hours = Double(parts[0]),
            let minutes = Double(parts[1]),
            let seconds = Double(parts[2]) else { return nil }
      return hours * 3600 + minutes * 60 + seconds
    }
    let content = try String(contentsOf: url, encoding: .utf8)
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return content.components(separatedBy: "\n\n").enumerated().compactMap { offset, block in
      let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
      let timing = lines[timingIndex].components(separatedBy: "-->")
      guard timing.count == 2,
            let start = seconds(timing[0].trimmingCharacters(in: .whitespaces)),
            let end = seconds(timing[1].trimmingCharacters(in: .whitespaces)),
            end > start else { return nil }
      let text = lines.dropFirst(timingIndex + 1).joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      return AISubtitleSegment(id: "srt-\(offset + 1)",
                               timeRange: AISubtitleTimeRange(start: start, end: end),
                               text: text,
                               language: language)
    }
  }

  @available(macOS 26.0, *)
  private static func translateSRTAvailable(srtPath: String,
                                            sourceCode: String,
                                            targetCode: String,
                                            outputPath: String,
                                            sampleName: String) async throws {
    let srtURL = URL(fileURLWithPath: srtPath).standardizedFileURL
    let source = AISubtitleLanguage(sourceCode)
    let transcript = try parsedSRT(at: srtURL, language: source)
    try await translateSegmentsAvailable(transcript,
                                         sourceCode: sourceCode,
                                         targetCode: targetCode,
                                         outputPath: outputPath,
                                         sampleName: sampleName,
                                         contextURL: srtURL)
  }

  private static func translateSRT(srtPath: String,
                                   sourceCode: String,
                                   targetCode: String,
                                   outputPath: String,
                                   sampleName: String) async throws {
    guard #available(macOS 26.0, *) else {
      throw EvaluationError.resource("Apple local AI requires macOS 26 or later.")
    }
    try await translateSRTAvailable(srtPath: srtPath,
                                    sourceCode: sourceCode,
                                    targetCode: targetCode,
                                    outputPath: outputPath,
                                    sampleName: sampleName)
  }

  private static func translateTranscript(transcriptPath: String,
                                          sourceCode: String,
                                          targetCode: String,
                                          outputPath: String,
                                          sampleName: String) async throws {
    guard #available(macOS 26.0, *) else {
      throw EvaluationError.resource("Apple local AI requires macOS 26 or later.")
    }
    try await translateTranscriptAvailable(transcriptPath: transcriptPath,
                                           sourceCode: sourceCode,
                                           targetCode: targetCode,
                                           outputPath: outputPath,
                                           sampleName: sampleName)
  }

  private static func copy(_ source: URL, to destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: source, to: destination)
  }
}
