import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
final class EvaluationAppleDictationTranscriber: AISubtitleTranscriber {
  let providerID = AISubtitleProviderID.apple
  let modelIdentifier = "apple-dictation-time-indexed-v1"

  func capability(for request: AISubtitleProviderRequest) -> AISubtitleProviderCapability {
    AISubtitleProviderCapability(providerID: providerID,
                                 role: .transcriber,
                                 status: request.sourceLanguage == nil ? .needsConfiguration : .available,
                                 reason: nil,
                                 supportsCloudProcessing: false,
                                 modelIdentifier: modelIdentifier)
  }

  func transcribe(_ chunk: AISubtitleAudioChunk,
                  request: AISubtitleProviderRequest,
                  completion: @escaping (Result<[AISubtitleSegment], AISubtitleError>) -> Void) {
    guard let language = request.sourceLanguage else {
      completion(.failure(AISubtitleError(code: "dictation_source_required",
                                          message: "Choose the spoken language.")))
      return
    }
    Task {
      do {
        let segments = try await transcribe(chunk, language: language)
        completion(.success(segments))
      } catch let error as AISubtitleError {
        completion(.failure(error))
      } catch {
        completion(.failure(AISubtitleError(code: "dictation_failed",
                                            message: error.localizedDescription)))
      }
    }
  }

  private func transcribe(_ chunk: AISubtitleAudioChunk,
                          language: AISubtitleLanguage) async throws -> [AISubtitleSegment] {
    guard let locale = await DictationTranscriber.supportedLocale(
      equivalentTo: Locale(identifier: language.code)) else {
      throw AISubtitleError(code: "dictation_language_unsupported",
                            message: "Apple Dictation does not support \(language.code).")
    }
    let transcriber = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
    if await AssetInventory.status(forModules: [transcriber]) != .installed,
       let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await installation.downloadAndInstall()
    }
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw AISubtitleError(code: "dictation_assets_required",
                            message: "Apple Dictation resources are not installed for \(locale.identifier).")
    }
    let audioFile = try AVAudioFile(forReading: chunk.url)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    async let resultFuture = collectResults(from: transcriber,
                                            chunkOffset: chunk.timeRange.start,
                                            language: language)
    if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
      try await analyzer.finalizeAndFinish(through: lastSample)
    } else {
      await analyzer.cancelAndFinishNow()
    }
    return try await resultFuture
  }

  private func collectResults(from transcriber: DictationTranscriber,
                              chunkOffset: Double,
                              language: AISubtitleLanguage) async throws -> [AISubtitleSegment] {
    var segments: [AISubtitleSegment] = []
    let timedTextSegmenter = AppleSpeechTimedTextSegmenter()
    for try await result in transcriber.results where result.isFinal {
      let timed = timedTextSegmenter.segments(from: result.text,
                                              chunkOffset: chunkOffset,
                                              language: language)
      if !timed.isEmpty {
        segments.append(contentsOf: timed)
        continue
      }
      let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let start = chunkOffset + result.range.start.seconds
      segments.append(AISubtitleSegment(
        timeRange: AISubtitleTimeRange(start: start,
                                      end: start + result.range.duration.seconds),
        text: text,
        language: language))
    }
    return segments
  }
}
