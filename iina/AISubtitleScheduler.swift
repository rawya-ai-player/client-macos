//
//  AISubtitleScheduler.swift
//  iina
//
//  Created by Codex on 2026/7/16.
//

import Foundation

final class AISubtitlePassThroughTranslator: AISubtitleTranslator {
  let providerID: AISubtitleProviderID
  let modelIdentifier = "identity"

  init(providerID: AISubtitleProviderID) {
    self.providerID = providerID
  }

  func capability(for request: AISubtitleProviderRequest) -> AISubtitleProviderCapability {
    AISubtitleProviderCapability(providerID: providerID,
                                 role: .translator,
                                 status: .available,
                                 reason: "Source and target languages are the same.",
                                 supportsCloudProcessing: providerID.isCloudProvider,
                                 modelIdentifier: modelIdentifier)
  }

  func translate(_ segments: [AISubtitleSegment],
                 request: AISubtitleProviderRequest,
                 completion: @escaping (Result<[AISubtitleCue], AISubtitleError>) -> Void) {
    completion(.success(segments.map {
      AISubtitleCue(id: $0.id,
                    timeRange: $0.timeRange,
                    text: $0.text,
                    language: request.targetLanguage)
    }))
  }
}

struct AISubtitleSpeechYieldPolicy {
  static func shouldPause(transcriptIsEmpty: Bool,
                          processedThrough: Double,
                          mediaDuration: Double,
                          hasRemainingRanges: Bool) -> Bool {
    guard transcriptIsEmpty, hasRemainingRanges, mediaDuration > 0 else { return false }
    let probeDuration = min(180, max(120, mediaDuration * 0.1))
    return processedThrough >= probeDuration
  }
}

enum AISubtitleChunkOverlapPolicy {
  static func newSpeechSegments(_ segments: [AISubtitleSegment],
                                in range: AISubtitleTimeRange,
                                overlapDuration: Double) -> [AISubtitleSegment] {
    guard range.start > 0, overlapDuration > 0 else { return segments }
    let previousChunkEnd = min(range.end, range.start + overlapDuration)
    return segments.filter { $0.timeRange.end > previousChunkEnd + 0.001 }
  }
}

final class AISubtitleScheduler {
  struct Configuration {
    // Kept for source compatibility with older callers. Full-video generation no longer
    // follows an ahead-of-playback window.
    var aheadDuration: Double = 300
    var refillThreshold: Double = 60
    var chunkPlanner = AISubtitleChunkPlanner()
    var publishesIntermediateArtifacts = false
  }

  typealias StateHandler = (AISubtitleTaskState) -> Void
  typealias SubtitleFileHandler = (AISubtitleCacheArtifacts) -> Void

  private let queue: DispatchQueue
  private let extractor: AISubtitleAudioExtracting
  private let transcriber: AISubtitleTranscriber
  private let translator: AISubtitleTranslator
  private let cacheStore: AISubtitleCacheStore
  private let configuration: Configuration
  private let fileManager: FileManager

  private var generation = UUID()
  private var media: AISubtitleMediaContext?
  private var mediaDuration: Double = 0
  private var request: AISubtitleProviderRequest?
  private var cacheKey: AISubtitleCacheKey?
  private var pendingRanges: [AISubtitleTimeRange] = []
  private var coveredRanges: [AISubtitleTimeRange] = []
  private var transcript: [AISubtitleSegment] = []
  private var translatedCues: [AISubtitleCue] = []
  private var isProcessing = false
  private var activeRange: AISubtitleTimeRange?
  private var shouldMonitorInitialSpeechYield = true
  private var stateHandler: StateHandler?
  private var subtitleFileHandler: SubtitleFileHandler?

  init(extractor: AISubtitleAudioExtracting,
       transcriber: AISubtitleTranscriber,
       translator: AISubtitleTranslator,
       cacheStore: AISubtitleCacheStore = AISubtitleCacheStore(),
       configuration: Configuration = Configuration(),
       fileManager: FileManager = .default,
       queue: DispatchQueue = DispatchQueue(label: "RawyaAISubtitleScheduler", qos: .utility)) {
    self.extractor = extractor
    self.transcriber = transcriber
    self.translator = translator
    self.cacheStore = cacheStore
    self.configuration = configuration
    self.fileManager = fileManager
    self.queue = queue
  }

  func start(media: AISubtitleMediaContext,
             mediaDuration: Double,
             cacheKey: AISubtitleCacheKey,
             playbackPosition: Double,
             stateHandler: @escaping StateHandler,
             subtitleFileHandler: @escaping SubtitleFileHandler) {
    queue.async {
      self.generation = UUID()
      self.media = media
      self.mediaDuration = max(0, mediaDuration)
      self.request = AISubtitleProviderRequest(sourceLanguage: media.sourceLanguage,
                                               targetLanguage: media.targetLanguage,
                                               media: media)
      self.cacheKey = cacheKey
      self.pendingRanges.removeAll()
      self.coveredRanges.removeAll()
      self.transcript.removeAll()
      self.translatedCues.removeAll()
      self.isProcessing = false
      self.activeRange = nil
      self.shouldMonitorInitialSpeechYield = true
      self.stateHandler = stateHandler
      self.subtitleFileHandler = subtitleFileHandler
      if let cached = try? self.cacheStore.cachedContent(for: cacheKey) {
        self.coveredRanges = self.mergedRanges(cached.metadata.coveredRanges)
        self.transcript = cached.transcript
        self.translatedCues = cached.cues
        if self.transcript.isEmpty, !self.coveredRanges.isEmpty {
          self.shouldMonitorInitialSpeechYield = false
        }
      }
      self.emit(AISubtitleTaskState(.preparing))
      guard self.mediaDuration > 0 else {
        self.fail(AISubtitleError(code: "invalid_media_duration",
                                  message: "The video duration is unavailable."))
        return
      }
      _ = playbackPosition
      self.enqueueWholeMedia()
      self.processNextIfNeeded()
    }
  }

  func updatePlaybackPosition(_ position: Double) {
    // Generation is intentionally independent of seeking, pausing, and playback speed.
    _ = position
  }

  func cancel() {
    queue.async {
      self.generation = UUID()
      (self.extractor as? AISubtitleCancelableProvider)?.cancelAll()
      (self.transcriber as? AISubtitleCancelableProvider)?.cancelAll()
      (self.translator as? AISubtitleCancelableProvider)?.cancelAll()
      self.pendingRanges.removeAll()
      self.media = nil
      self.request = nil
      self.cacheKey = nil
      self.isProcessing = false
      self.activeRange = nil
      self.emit(AISubtitleTaskState(.canceled))
      self.stateHandler = nil
      self.subtitleFileHandler = nil
    }
  }

  private func enqueueWholeMedia() {
    pendingRanges = configuration.chunkPlanner
      .ranges(covering: AISubtitleTimeRange(start: 0, end: mediaDuration))
      .filter { !isCovered($0) && $0 != activeRange }
  }

  private func processNextIfNeeded() {
    guard !isProcessing,
          let media = media,
          let request = request,
          let cacheKey = cacheKey else { return }
    guard let range = pendingRanges.first else {
      if !configuration.publishesIntermediateArtifacts,
         let artifacts = cacheStore.cachedArtifacts(for: cacheKey) {
        subtitleFileHandler?(artifacts)
      }
      emit(AISubtitleTaskState(.completed,
                               coveredRange: overallCoveredRange(),
                               progress: 1))
      return
    }
    pendingRanges.removeFirst()
    isProcessing = true
    activeRange = range
    let activeGeneration = generation
    let artifacts: AISubtitleCacheArtifacts
    do {
      artifacts = try cacheStore.layout.artifacts(for: cacheKey, createDirectories: true)
    } catch {
      fail(AISubtitleError(code: "cache_directory_failed", message: error.localizedDescription))
      return
    }
    let outputURL = artifacts.chunksDirectoryURL
      .appendingPathComponent(chunkFilename(for: range), isDirectory: false)
    emit(AISubtitleTaskState(.extracting,
                             currentRange: range,
                             coveredRange: overallCoveredRange(),
                             progress: progress))
    extractor.extract(media: media, timeRange: range, outputURL: outputURL) { result in
      self.queue.async {
        guard activeGeneration == self.generation else {
          if case .success(let chunk) = result {
            try? self.fileManager.removeItem(at: chunk.url)
          }
          return
        }
        switch result {
        case .failure(let error):
          self.fail(error)
        case .success(let chunk):
          self.emit(AISubtitleTaskState(.transcribing,
                                        currentRange: range,
                                        coveredRange: self.overallCoveredRange(),
                                        progress: self.progress))
          self.transcriber.transcribe(chunk, request: request) { result in
            self.queue.async {
              try? self.fileManager.removeItem(at: chunk.url)
              guard activeGeneration == self.generation else { return }
              switch result {
              case .failure(let error):
                self.fail(error)
              case .success(let segments):
                let newSpeechSegments = AISubtitleChunkOverlapPolicy.newSpeechSegments(
                  segments,
                  in: range,
                  overlapDuration: self.configuration.chunkPlanner.overlapDuration)
                let sourceLanguage = request.sourceLanguage
                  ?? newSpeechSegments.first?.language
                  ?? AISubtitleLanguage("und")
                let semanticSegments = AISubtitleSemanticSegmenter().assemble(
                  newSpeechSegments,
                  language: sourceLanguage)
                guard !semanticSegments.isEmpty else {
                  let shouldPause = self.shouldMonitorInitialSpeechYield
                    && AISubtitleSpeechYieldPolicy.shouldPause(
                      transcriptIsEmpty: self.transcript.isEmpty,
                      processedThrough: range.end,
                      mediaDuration: self.mediaDuration,
                      hasRemainingRanges: !self.pendingRanges.isEmpty
                    )
                  if shouldPause {
                    self.shouldMonitorInitialSpeechYield = false
                  }
                  self.finish(range: range,
                              newSegments: [],
                              newCues: [],
                              cacheKey: cacheKey,
                              stopAfterSaving: shouldPause ? AISubtitleError(
                                code: "ai_subtitle_possible_language_mismatch",
                                message: aiSubtitleLocalized(
                                  "ai_subtitle.possible_language_mismatch",
                                  fallback: "Rawya found no dialogue in the first few minutes. Check the audio language. If the opening is simply silent, generate again to continue from this point."
                                )
                              ) : nil)
                  return
                }
                self.shouldMonitorInitialSpeechYield = false
                let boundary = self.reconciledBoundary(
                  semanticSegments,
                  range: range,
                  language: sourceLanguage)
                self.emit(AISubtitleTaskState(.translating,
                                              currentRange: range,
                                              coveredRange: self.overallCoveredRange(),
                                              progress: self.progress))
                self.translator.translate(boundary.segments, request: request) { result in
                  self.queue.async {
                    guard activeGeneration == self.generation else { return }
                    switch result {
                    case .failure(let error):
                      self.fail(error)
                    case .success(let cues):
                      self.finish(range: range,
                                  newSegments: boundary.segments,
                                  newCues: cues,
                                  cacheKey: cacheKey,
                                  replacingSegmentIDs: boundary.replacingSegmentIDs)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  private func finish(range: AISubtitleTimeRange,
                      newSegments: [AISubtitleSegment],
                      newCues: [AISubtitleCue],
                      cacheKey: AISubtitleCacheKey,
                      replacingSegmentIDs: Set<String> = [],
                      stopAfterSaving: AISubtitleError? = nil) {
    if !replacingSegmentIDs.isEmpty {
      transcript.removeAll { replacingSegmentIDs.contains($0.id) }
      translatedCues.removeAll { replacingSegmentIDs.contains($0.id) }
    }
    transcript.append(contentsOf: newSegments)
    translatedCues.append(contentsOf: newCues)
    coveredRanges.append(range)
    coveredRanges = mergedRanges(coveredRanges)
    emit(AISubtitleTaskState(.assembling,
                             currentRange: range,
                             coveredRange: overallCoveredRange(),
                             progress: progress))
    do {
      let artifacts = try cacheStore.save(transcript: transcript,
                                          cues: translatedCues,
                                          coveredRanges: coveredRanges,
                                          for: cacheKey)
      if configuration.publishesIntermediateArtifacts,
         !pendingRanges.isEmpty,
         !newCues.isEmpty,
         !translatedCues.isEmpty {
        subtitleFileHandler?(artifacts)
      }
      emit(AISubtitleTaskState(.loading,
                               currentRange: range,
                               coveredRange: overallCoveredRange(),
                               progress: progress))
      isProcessing = false
      activeRange = nil
      if let stopAfterSaving {
        fail(stopAfterSaving)
      } else {
        processNextIfNeeded()
      }
    } catch {
      fail(AISubtitleError(code: "subtitle_cache_write_failed", message: error.localizedDescription))
    }
  }

  private func reconciledBoundary(_ newSegments: [AISubtitleSegment],
                                  range: AISubtitleTimeRange,
                                  language: AISubtitleLanguage) -> (segments: [AISubtitleSegment],
                                                                    replacingSegmentIDs: Set<String>) {
    guard range.start > 0, configuration.chunkPlanner.overlapDuration > 0 else {
      return (newSegments, [])
    }
    let previousTail = transcript.filter { $0.timeRange.end > range.start + 0.001 }
    guard !previousTail.isEmpty else { return (newSegments, []) }
    let replacingIDs = Set(previousTail.map(\.id))
    let reconciled = AISubtitleSemanticSegmenter().assemble(previousTail + newSegments,
                                                            language: language)
    return (reconciled, replacingIDs)
  }

  private func mergedRanges(_ ranges: [AISubtitleTimeRange]) -> [AISubtitleTimeRange] {
    var result: [AISubtitleTimeRange] = []
    for range in ranges.sorted(by: { $0.start < $1.start }) {
      guard var previous = result.popLast() else {
        result.append(range)
        continue
      }
      if range.start <= previous.end + 0.01 {
        previous.end = max(previous.end, range.end)
        result.append(previous)
      } else {
        result.append(previous)
        result.append(range)
      }
    }
    return result
  }

  private func isCovered(_ range: AISubtitleTimeRange) -> Bool {
    coveredRanges.contains { range.start >= $0.start && range.end <= $0.end }
  }

  private func overallCoveredRange() -> AISubtitleTimeRange? {
    guard let first = coveredRanges.first, let last = coveredRanges.last else { return nil }
    return AISubtitleTimeRange(start: first.start, end: last.end)
  }

  private var progress: Double? {
    guard mediaDuration > 0 else { return nil }
    let covered = coveredRanges.reduce(0) { $0 + $1.duration }
    return min(1, covered / mediaDuration)
  }

  private func chunkFilename(for range: AISubtitleTimeRange) -> String {
    let start = Int64((range.start * 1000).rounded())
    let end = Int64((range.end * 1000).rounded())
    return "chunk-\(start)-\(end).wav"
  }

  private func fail(_ error: AISubtitleError) {
    pendingRanges.removeAll()
    isProcessing = false
    activeRange = nil
    emit(AISubtitleTaskState(.failed,
                             coveredRange: overallCoveredRange(),
                             progress: progress,
                             error: error))
  }

  private func emit(_ state: AISubtitleTaskState) {
    stateHandler?(state)
  }
}
