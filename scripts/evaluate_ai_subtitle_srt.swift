#!/usr/bin/env swift

import Foundation

struct Cue: Codable {
  var index: Int
  var start: Double
  var end: Double
  var text: String

  var duration: Double { max(0, end - start) }
  var lines: [String] { text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
}

struct FileMetrics: Codable {
  var cueCount: Int
  var shortCueCount: Int
  var longCueCount: Int
  var overlapCount: Int
  var duplicateCount: Int
  var moreThanTwoLinesCount: Int
  var lineLengthViolationCount: Int
  var readingSpeedViolationCount: Int
  var edgePunctuationCount: Int
  var p50Duration: Double
  var p95Duration: Double
  var p50CharactersPerSecond: Double
  var p95CharactersPerSecond: Double
  var worstReadingSpeedCues: [CueScore]
}

struct CueScore: Codable {
  var index: Int
  var start: Double
  var end: Double
  var score: Double
  var text: String
}

struct PairMetrics: Codable {
  var alignmentPolicy: String
  var exactCueCountMatches: Bool
  var indexedTimingMismatchCount: Int
  var sourceOnlyCueCount: Int
  var targetOnlyCueCount: Int
  var timelineStartDifference: Double
  var timelineEndDifference: Double
}

struct EvaluationReport: Codable {
  var sourceLanguage: String
  var targetLanguage: String
  var source: FileMetrics
  var target: FileMetrics
  var pair: PairMetrics
  var referenceWordErrorRate: Double?
  var referenceCharacterErrorRate: Double?
}

enum EvaluationFailure: Error, CustomStringConvertible {
  case usage
  case malformed(String)

  var description: String {
    switch self {
    case .usage:
      return "Usage: evaluate_ai_subtitle_srt.swift <source.srt> <source-lang> <target.srt> <target-lang> [reference.srt]"
    case .malformed(let message):
      return message
    }
  }
}

func timestamp(_ value: String) -> Double? {
  let normalized = value.replacingOccurrences(of: ",", with: ".")
  let components = normalized.split(separator: ":")
  guard components.count == 3,
        let hours = Double(components[0]),
        let minutes = Double(components[1]),
        let seconds = Double(components[2]) else { return nil }
  return hours * 3600 + minutes * 60 + seconds
}

func parseSRT(at url: URL) throws -> [Cue] {
  let content = try String(contentsOf: url, encoding: .utf8)
    .replacingOccurrences(of: "\r\n", with: "\n")
    .replacingOccurrences(of: "\r", with: "\n")
  let blocks = content.components(separatedBy: "\n\n")
  return try blocks.compactMap { block in
    let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count >= 2 else { return nil }
    let timingIndex = lines.firstIndex(where: { $0.contains("-->") })
    guard let timingIndex else { return nil }
    let timing = lines[timingIndex].components(separatedBy: "-->")
    guard timing.count == 2,
          let start = timestamp(timing[0].trimmingCharacters(in: .whitespaces)),
          let end = timestamp(timing[1].trimmingCharacters(in: .whitespaces)) else {
      throw EvaluationFailure.malformed("Malformed timing in \(url.lastPathComponent): \(lines[timingIndex])")
    }
    let index = timingIndex > 0 ? Int(lines[timingIndex - 1]) ?? 0 : 0
    let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    return Cue(index: index, start: start, end: end, text: text)
  }
}

func primaryLanguage(_ code: String) -> String {
  code.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first.map(String.init) ?? code
}

func usesCompactScript(_ code: String) -> Bool {
  ["zh", "ja", "ko"].contains(primaryLanguage(code))
}

func readableCount(_ text: String) -> Int {
  text.filter { !$0.isWhitespace }.count
}

func percentile(_ values: [Double], _ percentile: Double) -> Double {
  guard !values.isEmpty else { return 0 }
  let sorted = values.sorted()
  let index = min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * percentile)) - 1))
  return sorted[index]
}

let edgePunctuation = CharacterSet(charactersIn: ".,;:!?…、。，；：！？")

func normalizedDuplicateText(_ text: String) -> String {
  text.lowercased().unicodeScalars.filter {
    !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
  }.map(String.init).joined()
}

func hasEdgePunctuation(_ text: String) -> Bool {
  let scalars = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
  guard let first = scalars.first, let last = scalars.last else { return false }
  return edgePunctuation.contains(first) || edgePunctuation.contains(last)
}

func metrics(for cues: [Cue], language: String) -> FileMetrics {
  let compact = usesCompactScript(language)
  let lineLimit = compact ? 22 : 42
  let speedLimit = compact ? 15.0 : 20.0
  let durations = cues.map(\.duration)
  let speeds = cues.map { cue in Double(readableCount(cue.text)) / max(0.001, cue.duration) }
  let worst = zip(cues, speeds).sorted { $0.1 > $1.1 }.prefix(10).map { cue, score in
    CueScore(index: cue.index, start: cue.start, end: cue.end, score: score, text: cue.text)
  }
  var overlapCount = 0
  var duplicateCount = 0
  for index in cues.indices.dropFirst() {
    if cues[index].start < cues[index - 1].end - 0.001 { overlapCount += 1 }
    let current = normalizedDuplicateText(cues[index].text)
    let previous = normalizedDuplicateText(cues[index - 1].text)
    if !current.isEmpty, current == previous { duplicateCount += 1 }
  }
  return FileMetrics(
    cueCount: cues.count,
    shortCueCount: cues.filter { $0.duration < 0.8 }.count,
    longCueCount: cues.filter { $0.duration > 6.001 }.count,
    overlapCount: overlapCount,
    duplicateCount: duplicateCount,
    moreThanTwoLinesCount: cues.filter { $0.lines.count > 2 }.count,
    lineLengthViolationCount: cues.filter { cue in cue.lines.contains { readableCount($0) > lineLimit } }.count,
    readingSpeedViolationCount: speeds.filter { $0 > speedLimit }.count,
    edgePunctuationCount: cues.filter { hasEdgePunctuation($0.text) }.count,
    p50Duration: percentile(durations, 0.50),
    p95Duration: percentile(durations, 0.95),
    p50CharactersPerSecond: percentile(speeds, 0.50),
    p95CharactersPerSecond: percentile(speeds, 0.95),
    worstReadingSpeedCues: worst)
}

func pairMetrics(source: [Cue], target: [Cue]) -> PairMetrics {
  let count = min(source.count, target.count)
  let mismatches = (0..<count).filter { index in
    abs(source[index].start - target[index].start) > 0.001
      || abs(source[index].end - target[index].end) > 0.001
  }.count
  let sourceStart = source.first?.start ?? 0
  let targetStart = target.first?.start ?? 0
  let sourceEnd = source.last?.end ?? 0
  let targetEnd = target.last?.end ?? 0
  return PairMetrics(alignmentPolicy: "shared-semantic-anchors",
                     exactCueCountMatches: source.count == target.count,
                     indexedTimingMismatchCount: mismatches,
                     sourceOnlyCueCount: max(0, source.count - target.count),
                     targetOnlyCueCount: max(0, target.count - source.count),
                     timelineStartDifference: abs(sourceStart - targetStart),
                     timelineEndDifference: abs(sourceEnd - targetEnd))
}

func normalizedWords(_ cues: [Cue]) -> [String] {
  cues.flatMap { cue in
    cue.text
      .replacingOccurrences(of: #"\[[^\]]+\]|\([^\)]+\)"#, with: " ", options: .regularExpression)
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
  }
}

func wordErrorRate(hypothesis: [String], reference: [String]) -> Double? {
  guard !reference.isEmpty else { return nil }
  var previous = Array(0...hypothesis.count)
  for (referenceIndex, referenceWord) in reference.enumerated() {
    var current = Array(repeating: 0, count: hypothesis.count + 1)
    current[0] = referenceIndex + 1
    for (hypothesisIndex, hypothesisWord) in hypothesis.enumerated() {
      current[hypothesisIndex + 1] = min(
        previous[hypothesisIndex + 1] + 1,
        current[hypothesisIndex] + 1,
        previous[hypothesisIndex] + (referenceWord == hypothesisWord ? 0 : 1))
    }
    previous = current
  }
  return Double(previous[hypothesis.count]) / Double(reference.count)
}

func normalizedCharacters(_ cues: [Cue]) -> [Character] {
  Array(cues.map(\.text).joined().lowercased().unicodeScalars.filter {
    CharacterSet.alphanumerics.contains($0)
  }.map(String.init).joined())
}

func characterErrorRate(hypothesis: [Character], reference: [Character]) -> Double? {
  guard !reference.isEmpty else { return nil }
  var previous = Array(0...hypothesis.count)
  for (referenceIndex, referenceCharacter) in reference.enumerated() {
    var current = Array(repeating: 0, count: hypothesis.count + 1)
    current[0] = referenceIndex + 1
    for (hypothesisIndex, hypothesisCharacter) in hypothesis.enumerated() {
      current[hypothesisIndex + 1] = min(
        previous[hypothesisIndex + 1] + 1,
        current[hypothesisIndex] + 1,
        previous[hypothesisIndex] + (referenceCharacter == hypothesisCharacter ? 0 : 1))
    }
    previous = current
  }
  return Double(previous[hypothesis.count]) / Double(reference.count)
}

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard arguments.count == 4 || arguments.count == 5 else { throw EvaluationFailure.usage }
  let source = try parseSRT(at: URL(fileURLWithPath: arguments[0]))
  let target = try parseSRT(at: URL(fileURLWithPath: arguments[2]))
  let referenceWER: Double?
  let referenceCER: Double?
  if arguments.count == 5 {
    let reference = try parseSRT(at: URL(fileURLWithPath: arguments[4]))
    let referenceStart = reference.first?.start ?? 0
    let referenceEnd = reference.last?.end ?? .greatestFiniteMagnitude
    let comparableSource = source.filter { $0.end > referenceStart && $0.start < referenceEnd }
    referenceWER = wordErrorRate(hypothesis: normalizedWords(comparableSource),
                                 reference: normalizedWords(reference))
    referenceCER = characterErrorRate(hypothesis: normalizedCharacters(comparableSource),
                                      reference: normalizedCharacters(reference))
  } else {
    referenceWER = nil
    referenceCER = nil
  }
  let report = EvaluationReport(sourceLanguage: arguments[1],
                                targetLanguage: arguments[3],
                                source: metrics(for: source, language: arguments[1]),
                                target: metrics(for: target, language: arguments[3]),
                                pair: pairMetrics(source: source, target: target),
                                referenceWordErrorRate: referenceWER,
                                referenceCharacterErrorRate: referenceCER)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  print(String(data: try encoder.encode(report), encoding: .utf8)!)
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
