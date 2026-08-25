//
//  AISubtitleFile.swift
//  iina
//
//  Created by Codex on 2026/7/16.
//

import Foundation
import NaturalLanguage

struct AISubtitleAssemblerOptions {
  var punctuationMergeGap: Double = 0.5
  var fillerMergeGap: Double = 0.65
  var maximumMergedFillerCharacterCount: Int = 12
  var maximumCJKCueCharacterCount: Int = 26
  var maximumLatinCueCharacterCount: Int = 72
}

struct AISubtitleSemanticSegmenterOptions {
  var maximumMergeGap: Double = 0.3
  var maximumDuration: Double = 12
  var maximumCompactCharacterCount: Int = 48
  var maximumLatinCharacterCount: Int = 100
  var shortFragmentDuration: Double = 0.45
  var unstableResultMergeGap: Double = 0.08
  var unstableResultDuration: Double = 1.1
  var maximumRecoveryDuration: Double = 30
  var maximumCompactRecoveryCharacterCount: Int = 160
  var maximumLatinRecoveryCharacterCount: Int = 240
  var maximumTranslationBlockDuration: Double = 8
  var maximumCompactTranslationBlockCharacterCount: Int = 48
  var maximumLatinTranslationBlockCharacterCount: Int = 100
  var maximumSentencesPerTranslationBlock: Int = 3
}

struct AISubtitleTargetTextNormalizer {
  func normalize(_ text: String, language: AISubtitleLanguage) -> String {
    let code = language.code.replacingOccurrences(of: "_", with: "-").lowercased()
    let transformName: String?
    if code == "zh-hans" || code.hasPrefix("zh-hans-") || code == "zh-cn" || code.hasPrefix("zh-cn-") {
      transformName = "Traditional-Simplified"
    } else if code == "zh-hant" || code.hasPrefix("zh-hant-") || code == "zh-tw" || code.hasPrefix("zh-tw-") {
      transformName = "Simplified-Traditional"
    } else {
      transformName = nil
    }
    guard let transformName,
          let normalized = text.applyingTransform(StringTransform(transformName), reverse: false) else {
      return text
    }
    return normalized
  }
}

struct AISubtitleTextPartitioner {
  func parts(_ text: String,
             maximumCharacterCount: Int,
             maximumSentenceCount: Int,
             minimumPartCount: Int = 1,
             compact: Bool,
             language: AISubtitleLanguage? = nil) -> [String] {
    let units = sentenceUnits(in: text).flatMap {
      chunks(in: $0,
             maximumCharacterCount: maximumCharacterCount,
             language: language)
    }
    var result: [String] = []
    var current = ""
    var currentSentenceCount = 0
    for unit in units {
      let unitSentenceCount = max(1, sentenceEndCount(in: unit))
      let candidate = joined(current, unit, compact: compact)
      if !current.isEmpty,
         (displayCharacterCount(candidate, compact: compact) > maximumCharacterCount
           || currentSentenceCount + unitSentenceCount > maximumSentenceCount) {
        result.append(current)
        current = unit
        currentSentenceCount = unitSentenceCount
      } else {
        current = candidate
        currentSentenceCount += unitSentenceCount
      }
    }
    if !current.isEmpty { result.append(current) }
    if result.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result = [text.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    while result.count < minimumPartCount {
      guard let index = result.indices.max(by: {
        readableCharacterCount(result[$0]) < readableCharacterCount(result[$1])
      }) else { break }
      let split = balancedParts(result[index],
                                count: 2,
                                compact: compact,
                                language: language)
      guard split.count == 2 else { break }
      result.replaceSubrange(index...index, with: split)
    }
    return result
  }

  func balancedParts(_ text: String,
                     count: Int,
                     compact: Bool,
                     language: AISubtitleLanguage? = nil) -> [String] {
    guard count > 1 else { return [text.trimmingCharacters(in: .whitespacesAndNewlines)] }
    var remaining = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
    var result: [String] = []
    for partIndex in 0..<(count - 1) {
      let remainingPartCount = count - partIndex
      guard remaining.count >= remainingPartCount else { return [text] }
      let ideal = max(1, remaining.count / remainingPartCount)
      let lower = max(1, ideal - max(2, ideal / 2))
      let upper = min(remaining.count - (remainingPartCount - 1),
                      ideal + max(2, ideal / 2))
      guard lower <= upper else { return [text] }
      let wordBoundaries = wordBoundaryOffsets(in: remaining)
      let splitIndex = (lower...upper).min { first, second in
        let firstScore = boundaryScore(at: first,
                                       in: remaining,
                                       wordBoundaries: wordBoundaries,
                                       language: language) * 100 + abs(first - ideal)
        let secondScore = boundaryScore(at: second,
                                        in: remaining,
                                        wordBoundaries: wordBoundaries,
                                        language: language) * 100 + abs(second - ideal)
        return firstScore < secondScore
      } ?? ideal
      let part = String(remaining[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !part.isEmpty else { return [text] }
      result.append(part)
      remaining.removeFirst(splitIndex)
      while remaining.first?.isWhitespace == true { remaining.removeFirst() }
    }
    let final = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !final.isEmpty else { return [text] }
    result.append(final)
    return result
  }

  func balancedLineParts(_ text: String,
                         maximumLineCharacterCount: Int,
                         compact: Bool,
                         language: AISubtitleLanguage? = nil) -> [String] {
    let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
    guard characters.count > maximumLineCharacterCount else { return [text] }
    let lower = max(1, characters.count - maximumLineCharacterCount)
    let upper = min(maximumLineCharacterCount, characters.count - 1)
    guard lower <= upper else {
      return balancedParts(text, count: 2, compact: compact, language: language)
    }
    let ideal = characters.count / 2
    let wordBoundaries = wordBoundaryOffsets(in: characters)
    let candidates = Array(lower...upper)
    let naturalCandidates = candidates.filter {
      boundaryScore(at: $0,
                    in: characters,
                    wordBoundaries: wordBoundaries,
                    language: language) <= 2
    }
    let pool = naturalCandidates.isEmpty ? candidates : naturalCandidates
    let splitIndex = pool.min { first, second in
      let firstDistance = abs(first - ideal)
      let secondDistance = abs(second - ideal)
      if firstDistance != secondDistance { return firstDistance < secondDistance }
      return boundaryScore(at: first,
                           in: characters,
                           wordBoundaries: wordBoundaries,
                           language: language)
        < boundaryScore(at: second,
                        in: characters,
                        wordBoundaries: wordBoundaries,
                        language: language)
    } ?? ideal
    let first = String(characters[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    let second = String(characters[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
    return first.isEmpty || second.isEmpty ? [text] : [first, second]
  }

  func sentenceEndCount(in text: String) -> Int {
    text.reduce(into: 0) { count, character in
      if "\u{3002}\u{FF01}\u{FF1F}!?".contains(character) { count += 1 }
    }
  }

  func readableCharacterCount(_ text: String) -> Int {
    text.filter { !$0.isWhitespace }.count
  }

  func displayCharacterCount(_ text: String, compact: Bool) -> Int {
    compact ? readableCharacterCount(text) : text.count
  }

  func isNaturalBoundary(between first: String,
                         and second: String,
                         language: AISubtitleLanguage) -> Bool {
    let characters = Array(first + second)
    let index = Array(first).count
    guard index > 0, index < characters.count else { return true }
    return boundaryScore(at: index,
                         in: characters,
                         wordBoundaries: wordBoundaryOffsets(in: characters),
                         language: language) <= 2
  }

  private func sentenceUnits(in text: String) -> [String] {
    let characters = Array(text)
    var result: [String] = []
    var current = ""
    for index in characters.indices {
      let character = characters[index]
      current.append(character)
      let nextIsBoundary = index == characters.index(before: characters.endIndex)
        || characters[characters.index(after: index)].isWhitespace
      let isSentenceEnd = "\u{3002}\u{FF01}\u{FF1F}!?".contains(character)
        || (character == "." && nextIsBoundary)
        || character == "\n"
      if isSentenceEnd {
        let unit = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unit.isEmpty { result.append(unit) }
        current = ""
      }
    }
    let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !remainder.isEmpty { result.append(remainder) }
    return result.isEmpty ? [text] : result
  }

  private func chunks(in text: String,
                      maximumCharacterCount: Int,
                      language: AISubtitleLanguage?) -> [String] {
    var remaining = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
    var result: [String] = []
    while displayCharacterCount(String(remaining), compact: language.map(usesCompactWritingSystem) ?? false)
            > maximumCharacterCount,
          remaining.count > 1 {
      let upper = min(remaining.count - 1, maximumCharacterCount)
      let lower = max(1, upper / 2)
      let wordBoundaries = wordBoundaryOffsets(in: remaining)
      let splitIndex = (lower...upper).min { first, second in
        let firstScore = boundaryScore(at: first,
                                       in: remaining,
                                       wordBoundaries: wordBoundaries,
                                       language: language) * 100 + (upper - first)
        let secondScore = boundaryScore(at: second,
                                        in: remaining,
                                        wordBoundaries: wordBoundaries,
                                        language: language) * 100 + (upper - second)
        return firstScore < secondScore
      } ?? upper
      let part = String(remaining[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !part.isEmpty { result.append(part) }
      remaining.removeFirst(splitIndex)
      while remaining.first?.isWhitespace == true { remaining.removeFirst() }
    }
    let final = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
    if !final.isEmpty,
       final.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains),
       !result.isEmpty {
      result[result.index(before: result.endIndex)] += final
    } else if !final.isEmpty {
      result.append(final)
    }
    return result
  }

  private func boundaryScore(at index: Int,
                             in characters: [Character],
                             wordBoundaries: Set<Int> = [],
                             language: AISubtitleLanguage? = nil) -> Int {
    guard index > 0, index < characters.count else { return 4 }
    let previous = characters[index - 1]
    let current = characters[index]
    if "\u{3002}\u{FF01}\u{FF1F}!?".contains(previous) { return 0 }
    if "\u{3001}\u{FF0C}\u{FF1B}\u{FF1A},;:".contains(previous) { return 1 }
    if isAwkwardJapaneseBoundary(at: index, in: characters, language: language) { return 5 }
    if previous.isWhitespace || current.isWhitespace { return 2 }
    if wordBoundaries.contains(index) { return 2 }
    return 3
  }

  private func isAwkwardJapaneseBoundary(at index: Int,
                                         in characters: [Character],
                                         language: AISubtitleLanguage?) -> Bool {
    guard primaryLanguageCode(language) == "ja" else { return false }
    let before = String(characters[..<index])
    let after = String(characters[index...])
    if before.hasSuffix("っ") && after.hasPrefix("ちゃ") { return true }
    if before.hasSuffix("な") && after.hasPrefix("るほど") { return true }
    let continuationPrefixes = [
      "たん", "た", "った", "って", "て", "で", "ない", "なかった", "ます", "ました",
      "ません", "です", "でした", "だった", "だ", "ん", "の", "に", "を", "が",
      "は", "へ", "も", "と", "か", "ね", "よ", "ば", "な", "く", "れ", "られ",
      "けど", "から", "ので"
    ]
    let incompleteSuffixes = ["かっ", "けれ", "でし", "まし", "ませ", "じゃ", "ちゃ", "多"]
    return continuationPrefixes.contains(where: after.hasPrefix)
      || incompleteSuffixes.contains(where: before.hasSuffix)
  }

  private func primaryLanguageCode(_ language: AISubtitleLanguage?) -> String? {
    language?.code.replacingOccurrences(of: "_", with: "-")
      .lowercased()
      .split(separator: "-")
      .first
      .map(String.init)
  }

  private func usesCompactWritingSystem(_ language: AISubtitleLanguage) -> Bool {
    primaryLanguageCode(language).map { ["zh", "ja", "ko"].contains($0) } ?? false
  }

  private func wordBoundaryOffsets(in characters: [Character]) -> Set<Int> {
    let text = String(characters)
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    var result: Set<Int> = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      result.insert(text.distance(from: text.startIndex, to: range.upperBound))
      return true
    }
    return result
  }

  private func joined(_ first: String, _ second: String, compact: Bool) -> String {
    guard !first.isEmpty else { return second }
    guard !second.isEmpty else { return first }
    return compact ? first + second : first + " " + second
  }
}

/// Turns unstable final speech results into short, translatable phrases while preserving
/// meaningful speech turns. This intentionally does not try to infer speakers.
struct AISubtitleSemanticSegmenter {
  var options = AISubtitleSemanticSegmenterOptions()
  private let partitioner = AISubtitleTextPartitioner()

  func assemble(_ segments: [AISubtitleSegment], language: AISubtitleLanguage) -> [AISubtitleSegment] {
    let compact = usesCompactWritingSystem(language)
    let sorted = segments
      .compactMap(normalized)
      .sorted {
        if $0.timeRange.start == $1.timeRange.start {
          return $0.timeRange.end < $1.timeRange.end
        }
        return $0.timeRange.start < $1.timeRange.start
      }

    var result: [AISubtitleSegment] = []
    for segment in sorted {
      guard var previous = result.popLast() else {
        result.append(segment)
        continue
      }
      let gap = segment.timeRange.start - previous.timeRange.end
      if previous.text == segment.text && gap < 0 {
        previous.timeRange.end = max(previous.timeRange.end, segment.timeRange.end)
        result.append(previous)
        continue
      }
      if let revisedText = mergedOverlapRevision(previous, segment) {
        previous.timeRange.end = max(previous.timeRange.end, segment.timeRange.end)
        previous.text = revisedText
        result.append(previous)
        continue
      }
      if shouldAbsorbRepeatedSuffix(previous, segment, gap: gap) {
        previous.timeRange.end = max(previous.timeRange.end, segment.timeRange.end)
        result.append(previous)
        continue
      }
      if shouldMerge(previous, segment, gap: gap, compact: compact, language: language) {
        previous.timeRange.end = max(previous.timeRange.end, segment.timeRange.end)
        previous.text = joined(previous.text, segment.text, compact: compact)
        result.append(previous)
        continue
      }

      var current = segment
      if current.timeRange.start < previous.timeRange.end {
        current.timeRange.start = previous.timeRange.end
      }
      result.append(previous)
      if !current.timeRange.isEmpty { result.append(current) }
    }
    return result.flatMap { translationBlocks(for: $0, language: language, compact: compact) }
  }

  private func translationBlocks(for segment: AISubtitleSegment,
                                 language: AISubtitleLanguage,
                                 compact: Bool) -> [AISubtitleSegment] {
    let maximumCharacterCount = compact
      ? options.maximumCompactTranslationBlockCharacterCount
      : options.maximumLatinTranslationBlockCharacterCount
    let minimumPartCount = max(1, Int(ceil(segment.timeRange.duration
      / options.maximumTranslationBlockDuration)))
    let parts = partitioner.parts(segment.text,
                                  maximumCharacterCount: maximumCharacterCount,
                                  maximumSentenceCount: options.maximumSentencesPerTranslationBlock,
                                  minimumPartCount: minimumPartCount,
                                  compact: compact,
                                  language: language)
    guard parts.count > 1 else { return [segment] }
    let weights = parts.map { max(1, partitioner.readableCharacterCount($0)) }
    var remainingWeight = weights.reduce(0, +)
    var remainingDuration = segment.timeRange.duration
    var cursor = segment.timeRange.start
    return parts.enumerated().map { index, text in
      let end: Double
      if index == parts.count - 1 {
        end = segment.timeRange.end
      } else {
        let remainingPartCount = parts.count - index - 1
        let minimumAllocation = max(0,
                                    remainingDuration
                                      - options.maximumTranslationBlockDuration
                                      * Double(remainingPartCount))
        let proportionalAllocation = remainingWeight > 0
          ? remainingDuration * Double(weights[index]) / Double(remainingWeight)
          : remainingDuration / Double(remainingPartCount + 1)
        let allocation = min(options.maximumTranslationBlockDuration,
                             max(minimumAllocation, proportionalAllocation))
        end = min(segment.timeRange.end, cursor + allocation)
      }
      defer {
        remainingDuration -= end - cursor
        remainingWeight -= weights[index]
        cursor = end
      }
      return AISubtitleSegment(id: "\(segment.id)-context-\(index + 1)",
                               timeRange: AISubtitleTimeRange(start: cursor, end: end),
                               text: text,
                               language: language,
                               confidence: segment.confidence)
    }
  }

  private func shouldMerge(_ first: AISubtitleSegment,
                           _ second: AISubtitleSegment,
                           gap: Double,
                           compact: Bool,
                           language: AISubtitleLanguage) -> Bool {
    guard gap >= -0.05, gap <= options.maximumMergeGap else { return false }
    let normalizedGap = max(0, gap)
    let combinedDuration = max(first.timeRange.end, second.timeRange.end) - first.timeRange.start
    let combinedCount = readableCharacterCount(first.text + second.text)
    let maximumCount = compact
      ? options.maximumCompactCharacterCount
      : options.maximumLatinCharacterCount
    let hasBrokenWordBoundary = normalizedGap <= options.unstableResultMergeGap
      && compact
      && !partitioner.isNaturalBoundary(between: first.text,
                                        and: second.text,
                                        language: language)
    if hasBrokenWordBoundary {
      let recoveryMaximumCount = compact
        ? options.maximumCompactRecoveryCharacterCount
        : options.maximumLatinRecoveryCharacterCount
      return combinedDuration <= options.maximumRecoveryDuration
        && combinedCount <= recoveryMaximumCount
    }
    guard combinedDuration <= options.maximumDuration, combinedCount <= maximumCount else { return false }
    if isPunctuationOnly(second.text) { return true }
    if isFiller(first.text) && isFiller(second.text) { return true }
    if normalizedGap <= options.unstableResultMergeGap,
       min(first.timeRange.duration, second.timeRange.duration) < options.unstableResultDuration,
       !hasTerminalSentenceBoundary(first.text),
       !isStandaloneResponse(first.text, language: language),
       !isStandaloneResponse(second.text, language: language) {
      return true
    }
    return isFragment(first, compact: compact, language: language)
      || isFragment(second, compact: compact, language: language)
  }

  private func shouldAbsorbRepeatedSuffix(_ first: AISubtitleSegment,
                                          _ second: AISubtitleSegment,
                                          gap: Double) -> Bool {
    let isShortContinuation = gap >= -0.05
      && gap <= options.unstableResultMergeGap
      && second.timeRange.duration <= options.unstableResultDuration
    let isOverlappingRevision = gap < -0.05
      && second.timeRange.end >= first.timeRange.end
      && second.timeRange.end - first.timeRange.end <= 0.5
    guard isShortContinuation || isOverlappingRevision else { return false }
    let firstText = comparableText(first.text)
    let secondText = comparableText(second.text)
    return secondText.count >= 4
      && firstText.count > secondText.count
      && firstText.hasSuffix(secondText)
  }

  private func mergedOverlapRevision(_ first: AISubtitleSegment,
                                     _ second: AISubtitleSegment) -> String? {
    guard second.timeRange.start < first.timeRange.end,
          second.timeRange.end >= first.timeRange.end,
          second.timeRange.end - first.timeRange.end <= 0.75 else { return nil }
    let firstTokens = speechTokens(first.text)
    let secondTokens = speechTokens(second.text)
    guard firstTokens.count >= 3, secondTokens.count >= 3 else { return nil }
    let maximumOverlap = min(firstTokens.count, secondTokens.count)
    guard let overlapCount = stride(from: maximumOverlap, through: 3, by: -1).first(where: { count in
      let firstSuffix = firstTokens.suffix(count).map { $0.comparable }
      let secondPrefix = secondTokens.prefix(count).map { $0.comparable }
      return firstSuffix.elementsEqual(secondPrefix)
    }) else { return nil }
    guard overlapCount < secondTokens.count else { return first.text }
    let uniqueTail = secondTokens.dropFirst(overlapCount).map { $0.original }.joined(separator: " ")
    let prefix = first.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return prefix.isEmpty ? uniqueTail : prefix + " " + uniqueTail
  }

  private func speechTokens(_ text: String) -> [(original: String, comparable: String)] {
    text.components(separatedBy: .whitespacesAndNewlines).compactMap { token in
      let comparable = token.lowercased().unicodeScalars
        .filter(CharacterSet.alphanumerics.contains)
        .map(String.init)
        .joined()
      guard !comparable.isEmpty else { return nil }
      let canonical: String
      if comparable.count > 4, comparable.hasSuffix("s"), !comparable.hasSuffix("ss") {
        canonical = String(comparable.dropLast())
      } else {
        canonical = comparable
      }
      return (token, canonical)
    }
  }

  private func comparableText(_ text: String) -> String {
    text.lowercased().unicodeScalars.filter {
      !CharacterSet.whitespacesAndNewlines.contains($0)
        && !CharacterSet.punctuationCharacters.contains($0)
    }.map(String.init).joined()
  }

  private func isFragment(_ segment: AISubtitleSegment,
                          compact: Bool,
                          language: AISubtitleLanguage) -> Bool {
    let count = readableCharacterCount(segment.text)
    if compact, count <= 1, !isStandaloneCompactResponse(segment.text, language: language) { return true }
    if !compact, count <= 3, segment.timeRange.duration <= 0.6 { return true }
    let shortLimit = compact ? 4 : 8
    return segment.timeRange.duration <= options.shortFragmentDuration && count <= shortLimit
  }

  private func isStandaloneCompactResponse(_ text: String,
                                           language: AISubtitleLanguage) -> Bool {
    let normalized = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    let primaryCode = language.code.replacingOccurrences(of: "_", with: "-")
      .lowercased()
      .split(separator: "-")
      .first
      .map(String.init)
    switch primaryCode {
    case "zh":
      return ["嗯", "啊", "哦", "好", "对", "是", "不", "行"].contains(normalized)
    case "ja":
      return ["あ", "え", "ん"].contains(normalized)
    case "ko":
      return ["응", "어", "네"].contains(normalized)
    default:
      return false
    }
  }

  private func isStandaloneResponse(_ text: String,
                                    language: AISubtitleLanguage) -> Bool {
    let normalized = text.lowercased()
      .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    let primaryCode = language.code.replacingOccurrences(of: "_", with: "-")
      .lowercased()
      .split(separator: "-")
      .first
      .map(String.init)
    switch primaryCode {
    case "zh":
      return ["嗯", "啊", "哦", "好", "好的", "对", "是", "是的", "不", "不是", "行", "可以"].contains(normalized)
    case "ja":
      return ["あ", "え", "ん", "はい", "うん", "ええ", "そう", "そうです", "なるほど", "大丈夫"].contains(normalized)
    case "ko":
      return ["응", "어", "네", "아니", "맞아"].contains(normalized)
    default:
      return ["yes", "yeah", "no", "okay", "ok", "right", "sure"].contains(normalized)
    }
  }

  private func hasTerminalSentenceBoundary(_ text: String) -> Bool {
    var characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
    while let last = characters.last,
          "\"'\u{2019}\u{201D}\u{3009}\u{300B}\u{300D}\u{300F}\u{3011})]}\u{FF09}".contains(last) {
      characters.removeLast()
    }
    guard let last = characters.last else { return false }
    return "\u{3002}\u{FF01}\u{FF1F}!?".contains(last) || last == "."
  }

  private func normalized(_ segment: AISubtitleSegment) -> AISubtitleSegment? {
    let text = segment.text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .replacingOccurrences(of: #"\s+([,.;:!?])"#,
                            with: "$1",
                            options: .regularExpression)
    guard !text.isEmpty, !segment.timeRange.isEmpty else { return nil }
    var result = segment
    result.text = text
    return result
  }

  private func joined(_ first: String, _ second: String, compact: Bool) -> String {
    if isPunctuationOnly(second) { return first + second }
    return compact ? first + second : first + " " + second
  }

  private func readableCharacterCount(_ text: String) -> Int {
    text.filter { !$0.isWhitespace }.count
  }

  private func isPunctuationOnly(_ text: String) -> Bool {
    !text.unicodeScalars.isEmpty
      && text.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
  }

  private func isFiller(_ text: String) -> Bool {
    let normalized = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    return ["嗯", "啊", "哦", "呃", "唔", "あ", "え", "うん", "えっと", "uh", "um", "hmm", "oh", "ah"]
      .contains(normalized)
  }

  private func usesCompactWritingSystem(_ language: AISubtitleLanguage) -> Bool {
    let primaryCode = language.code.replacingOccurrences(of: "_", with: "-")
      .lowercased()
      .split(separator: "-")
      .first
      .map(String.init)
    return primaryCode.map { ["zh", "ja", "ko"].contains($0) } ?? false
  }
}

struct AISubtitleTimelineAssembler {
  var options = AISubtitleAssemblerOptions()
  private static let trailingPunctuation = Set(".,;:!?\u{2026}\u{3001}\u{3002}\u{FF0C}\u{FF0E}\u{FF1B}\u{FF1A}\u{FF01}\u{FF1F}")
  private static let closingCharacters = Set("\"'\u{2019}\u{201D}\u{3009}\u{300B}\u{300D}\u{300F}\u{3011}\u{3015}\u{3017}\u{3019}\u{301B})]}\u{FF09}")
  private static let fillerTokens: Set<String> = [
    "\u{55EF}", "\u{554A}", "\u{54E6}", "\u{5443}", "\u{5514}", "\u{54CE}", "\u{5440}", "\u{8BF6}", "\u{6B38}", "\u{54FC}", "\u{54C8}",
    "\u{3042}", "\u{3042}\u{3042}", "\u{3048}", "\u{3048}\u{3048}", "\u{3046}\u{3093}", "\u{3046}\u{30FC}\u{3093}", "\u{3048}\u{3063}\u{3068}", "\u{3042}\u{306E}", "\u{307E}\u{3042}",
    "\u{C74C}", "\u{C5B4}", "\u{C544}", "\u{C751}",
    "uh", "um", "hmm", "mm", "oh", "ah", "er"
  ]

  func assemble(_ segments: [AISubtitleSegment], targetLanguage: AISubtitleLanguage) -> [AISubtitleCue] {
    let sorted = segments
      .compactMap(normalizedSegment)
      .sorted {
        if $0.timeRange.start == $1.timeRange.start {
          return $0.timeRange.end < $1.timeRange.end
        }
        return $0.timeRange.start < $1.timeRange.start
      }

    var cues: [AISubtitleCue] = []
    for segment in sorted {
      var cue = AISubtitleCue(id: segment.id,
                              timeRange: segment.timeRange,
                              text: segment.text,
                              language: targetLanguage)
      guard var previous = cues.popLast() else {
        cues.append(cue)
        continue
      }

      let gap = cue.timeRange.start - previous.timeRange.end
      if previous.text == cue.text && gap < 0 {
        previous.timeRange.end = max(previous.timeRange.end, cue.timeRange.end)
        cues.append(previous)
        continue
      }

      if isPunctuationOnly(cue.text), gap >= 0, gap <= options.punctuationMergeGap {
        previous.timeRange.end = max(previous.timeRange.end, cue.timeRange.end)
        previous.text += cue.text
        cues.append(previous)
        continue
      }

      if shouldMergeFillers(previous.text, cue.text, gap: gap) {
        previous.timeRange.end = max(previous.timeRange.end, cue.timeRange.end)
        previous.text += " " + cue.text
        cues.append(previous)
        continue
      }

      if cue.timeRange.start < previous.timeRange.end {
        cue.timeRange.start = previous.timeRange.end
      }
      guard !cue.timeRange.isEmpty else {
        cues.append(previous)
        continue
      }

      // A final speech result is the closest signal available for a turn of speech.
      // Keep adjacent results separate so consecutive speakers are not collapsed into one cue.
      cues.append(previous)
      cues.append(cue)
    }
    let splitCues = cues.flatMap { splitCueForReading($0, targetLanguage: targetLanguage) }
    return mergingTrailingClosingCues(splitCues)
      .compactMap(removingEdgePunctuation)
  }

  private func splitCueForReading(_ cue: AISubtitleCue,
                                  targetLanguage: AISubtitleLanguage) -> [AISubtitleCue] {
    let maximumCharacterCount = usesCompactWritingSystem(targetLanguage)
      ? options.maximumCJKCueCharacterCount
      : options.maximumLatinCueCharacterCount
    let sentenceParts = sentenceParts(in: cue.text)
      .flatMap { chunks(in: $0, maximumCharacterCount: maximumCharacterCount) }
      .filter { !$0.isEmpty }
    guard sentenceParts.count > 1 else { return [cue] }

    let weights = sentenceParts.map { max(1, readableCharacterCount(in: $0)) }
    let totalWeight = weights.reduce(0, +)
    let duration = cue.timeRange.duration
    var cursor = cue.timeRange.start
    return sentenceParts.enumerated().map { index, text in
      let end: Double
      if index == sentenceParts.count - 1 {
        end = cue.timeRange.end
      } else {
        end = min(cue.timeRange.end,
                  cursor + duration * Double(weights[index]) / Double(totalWeight))
      }
      defer { cursor = end }
      return AISubtitleCue(id: "\(cue.id)-\(index + 1)",
                           timeRange: AISubtitleTimeRange(start: cursor, end: end),
                           text: text,
                           originalText: cue.originalText,
                           language: cue.language)
    }
  }

  private func sentenceParts(in text: String) -> [String] {
    let characters = Array(text)
    var parts: [String] = []
    var current = ""
    for index in characters.indices {
      let character = characters[index]
      current.append(character)
      let nextIsBoundary = index == characters.index(before: characters.endIndex)
        || characters[characters.index(after: index)].isWhitespace
      let isSentenceEnd = "。！？!?".contains(character)
        || (character == "." && nextIsBoundary)
        || character == "\n"
      if isSentenceEnd {
        let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !part.isEmpty { parts.append(part) }
        current = ""
      }
    }
    let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !remainder.isEmpty { parts.append(remainder) }
    return parts.isEmpty ? [text] : parts
  }

  private func chunks(in text: String, maximumCharacterCount: Int) -> [String] {
    var remaining = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
    var result: [String] = []
    while remaining.count > maximumCharacterCount {
      let lowerBound = max(1, maximumCharacterCount / 2)
      let candidates = Array(remaining.prefix(maximumCharacterCount))
      var splitIndex = candidates.indices.reversed().first { index in
        index >= lowerBound && "，、；：,;:".contains(candidates[index])
      }
      if splitIndex == nil {
        splitIndex = candidates.indices.reversed().first { index in
          index >= lowerBound && candidates[index].isWhitespace
        }
      }
      let end = min(remaining.count, (splitIndex ?? maximumCharacterCount - 1) + 1)
      let part = String(remaining[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !part.isEmpty { result.append(part) }
      remaining.removeFirst(end)
      while remaining.first?.isWhitespace == true { remaining.removeFirst() }
    }
    let last = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
    if !last.isEmpty { result.append(last) }
    return result
  }

  private func readableCharacterCount(in text: String) -> Int {
    text.filter { !$0.isWhitespace }.count
  }

  private func usesCompactWritingSystem(_ language: AISubtitleLanguage) -> Bool {
    let primaryCode = language.code.replacingOccurrences(of: "_", with: "-")
      .lowercased()
      .split(separator: "-")
      .first
      .map(String.init)
    return primaryCode.map { ["zh", "ja", "ko"].contains($0) } ?? false
  }

  private func normalizedSegment(_ segment: AISubtitleSegment) -> AISubtitleSegment? {
    let text = segment.text
      .components(separatedBy: .newlines)
      .map { line in
        line.components(separatedBy: .whitespacesAndNewlines)
          .filter { !$0.isEmpty }
          .joined(separator: " ")
      }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    guard !text.isEmpty, !segment.timeRange.isEmpty else { return nil }
    var normalized = segment
    normalized.text = text.replacingOccurrences(of: #"\s+([,.;:!?])"#,
                                                with: "$1",
                                                options: .regularExpression)
    return normalized
  }

  private func isPunctuationOnly(_ text: String) -> Bool {
    !text.unicodeScalars.isEmpty
      && text.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
  }

  private func shouldMergeFillers(_ first: String, _ second: String, gap: Double) -> Bool {
    guard gap >= 0, gap <= options.fillerMergeGap,
          isFillerOnly(first), isFillerOnly(second) else { return false }
    return readableCharacterCount(in: first + second) <= options.maximumMergedFillerCharacterCount
  }

  private func isFillerOnly(_ text: String) -> Bool {
    let tokens = text.lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .map { token in
        String(token.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })
      }
      .filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return false }
    if tokens.count > 1 { return tokens.allSatisfy(Self.fillerTokens.contains) }
    let normalized = tokens[0]
    if Self.fillerTokens.contains(normalized) { return true }
    guard let first = normalized.first,
          Self.fillerTokens.contains(String(first)) else { return false }
    return normalized.allSatisfy { $0 == first }
  }

  private func mergingTrailingClosingCues(_ cues: [AISubtitleCue]) -> [AISubtitleCue] {
    var result: [AISubtitleCue] = []
    for cue in cues {
      let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty,
         text.allSatisfy(Self.closingCharacters.contains),
         var previous = result.popLast() {
        previous.text += text
        previous.timeRange.end = max(previous.timeRange.end, cue.timeRange.end)
        result.append(previous)
      } else {
        result.append(cue)
      }
    }
    return result
  }

  private func removingEdgePunctuation(_ cue: AISubtitleCue) -> AISubtitleCue? {
    var text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
    var characters = Array(text)
    while let first = characters.first, Self.trailingPunctuation.contains(first) {
      characters.removeFirst()
    }
    var closingSuffix: [Character] = []
    while let last = characters.last, Self.closingCharacters.contains(last) {
      closingSuffix.append(characters.removeLast())
    }
    while let last = characters.last, Self.trailingPunctuation.contains(last) {
      characters.removeLast()
    }
    characters.append(contentsOf: closingSuffix.reversed())
    text = String(characters).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    var normalized = cue
    normalized.text = text
    return normalized
  }

}

struct AISubtitlePairedTimeline {
  var transcript: [AISubtitleSegment]
  var originalCues: [AISubtitleCue]
  var translatedCues: [AISubtitleCue]
}

struct AISubtitleReadingOptions {
  var minimumDisplayDuration: Double = 1
  var maximumDisplayDuration: Double = 6
  var compactCharactersPerSecond: Double = 11
  var latinCharactersPerSecond: Double = 17
  var compactLineCharacterCount: Int = 22
  var latinLineCharacterCount: Int = 42
  var maximumCompactCueCharacterCount: Int = 28
  var maximumLatinCueCharacterCount: Int = 72
  var maximumSentencesPerCue: Int = 1
  var minimumSplitCueDuration: Double = 1.1
}

/// Produces one timing track for both languages. Source and target may wrap differently,
/// but a cue transition always happens at the same time in both files.
struct AISubtitlePairedTimelineAssembler {
  var readingOptions = AISubtitleReadingOptions()
  private let partitioner = AISubtitleTextPartitioner()
  private static let trailingPunctuation = Set(".,;:!?\u{2026}\u{3001}\u{3002}\u{FF0C}\u{FF0E}\u{FF1B}\u{FF1A}\u{FF01}\u{FF1F}")
  private static let closingCharacters = Set("\"'\u{2019}\u{201D}\u{3009}\u{300B}\u{300D}\u{300F}\u{3011}\u{3015}\u{3017}\u{3019}\u{301B})]}\u{FF09}")

  private struct Pair {
    var id: String
    var timeRange: AISubtitleTimeRange
    var sourceText: String
    var translatedText: String
  }

  func assemble(transcript: [AISubtitleSegment],
                translatedCues: [AISubtitleCue],
                sourceLanguage: AISubtitleLanguage,
                targetLanguage: AISubtitleLanguage) -> AISubtitlePairedTimeline {
    let translatedByID = Dictionary(translatedCues.map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
    let sameLanguage = sourceLanguage.isEquivalent(to: targetLanguage)
    let sorted = transcript
      .compactMap(normalizedSegment)
      .sorted {
        if $0.timeRange.start == $1.timeRange.start {
          return $0.timeRange.end < $1.timeRange.end
        }
        return $0.timeRange.start < $1.timeRange.start
      }

    var pairs: [Pair] = []
    for segment in sorted {
      let translatedText: String
      if let cue = translatedByID[segment.id] {
        translatedText = cue.text
      } else if sameLanguage {
        translatedText = segment.text
      } else {
        continue
      }
      guard let sourceText = removingEdgePunctuation(segment.text),
            let targetText = removingEdgePunctuation(translatedText) else { continue }
      var pair = Pair(id: segment.id,
                      timeRange: segment.timeRange,
                      sourceText: sourceText,
                      translatedText: targetText)
      guard var previous = pairs.popLast() else {
        pairs.append(pair)
        continue
      }
      let gap = pair.timeRange.start - previous.timeRange.end
      if previous.sourceText == pair.sourceText && gap < 0 {
        previous.timeRange.end = max(previous.timeRange.end, pair.timeRange.end)
        pairs.append(previous)
        continue
      }
      if pair.timeRange.start < previous.timeRange.end {
        pair.timeRange.start = previous.timeRange.end
      }
      pairs.append(previous)
      if !pair.timeRange.isEmpty { pairs.append(pair) }
    }

    pairs = pairs.flatMap {
      displayPairs(from: $0,
                   sourceLanguage: sourceLanguage,
                   targetLanguage: targetLanguage)
    }

    for index in pairs.indices {
      pairs[index].timeRange.end = min(
        pairs[index].timeRange.end,
        pairs[index].timeRange.start + readingOptions.maximumDisplayDuration)
    }

    for index in pairs.indices.dropLast() {
      let requiredDuration = readableDuration(sourceText: pairs[index].sourceText,
                                              sourceLanguage: sourceLanguage,
                                              translatedText: pairs[index].translatedText,
                                              targetLanguage: targetLanguage)
      let availableEnd = pairs[pairs.index(after: index)].timeRange.start
      pairs[index].timeRange.end = min(availableEnd,
                                       max(pairs[index].timeRange.end,
                                           pairs[index].timeRange.start + requiredDuration))
    }

    let normalizedTranscript = pairs.map {
      AISubtitleSegment(id: $0.id,
                        timeRange: $0.timeRange,
                        text: $0.sourceText,
                        language: sourceLanguage)
    }
    let originalCues = pairs.map {
      AISubtitleCue(id: $0.id,
                    timeRange: $0.timeRange,
                    text: wrappedForDisplay($0.sourceText, language: sourceLanguage),
                    language: sourceLanguage)
    }
    let normalizedTranslatedCues = pairs.map {
      AISubtitleCue(id: $0.id,
                    timeRange: $0.timeRange,
                    text: wrappedForDisplay($0.translatedText, language: targetLanguage),
                    originalText: $0.sourceText,
                    language: targetLanguage)
    }
    return AISubtitlePairedTimeline(transcript: normalizedTranscript,
                                    originalCues: originalCues,
                                    translatedCues: normalizedTranslatedCues)
  }

  private func displayPairs(from pair: Pair,
                            sourceLanguage: AISubtitleLanguage,
                            targetLanguage: AISubtitleLanguage) -> [Pair] {
    let sourceCompact = usesCompactWritingSystem(sourceLanguage)
    let targetCompact = usesCompactWritingSystem(targetLanguage)
    let sourceMaximum = sourceCompact
      ? readingOptions.maximumCompactCueCharacterCount
      : readingOptions.maximumLatinCueCharacterCount
    let targetMaximum = targetCompact
      ? readingOptions.maximumCompactCueCharacterCount
      : readingOptions.maximumLatinCueCharacterCount
    let sourceNaturalParts = partitioner.parts(
      pair.sourceText,
      maximumCharacterCount: sourceMaximum,
      maximumSentenceCount: readingOptions.maximumSentencesPerCue,
      compact: sourceCompact,
      language: sourceLanguage)
    let translatedNaturalParts = partitioner.parts(
      pair.translatedText,
      maximumCharacterCount: targetMaximum,
      maximumSentenceCount: readingOptions.maximumSentencesPerCue,
      compact: targetCompact,
      language: targetLanguage)
    let desiredCount = max(sourceNaturalParts.count, translatedNaturalParts.count)
    let sourceLineCapacity = 2 * (sourceCompact
      ? readingOptions.compactLineCharacterCount
      : readingOptions.latinLineCharacterCount)
    let targetLineCapacity = 2 * (targetCompact
      ? readingOptions.compactLineCharacterCount
      : readingOptions.latinLineCharacterCount)
    let minimumCountForTwoLineDisplay = max(
      1,
      Int(ceil(Double(partitioner.displayCharacterCount(pair.sourceText, compact: sourceCompact))
        / Double(sourceLineCapacity))),
      Int(ceil(Double(partitioner.displayCharacterCount(pair.translatedText, compact: targetCompact))
        / Double(targetLineCapacity))))
    let maximumCountForDuration = max(1, Int(floor(pair.timeRange.duration
      / readingOptions.minimumSplitCueDuration)))
    let count = min(desiredCount,
                    max(maximumCountForDuration, minimumCountForTwoLineDisplay))
    guard count > 1 else { return [pair] }

    let sourceParts = expandedParts(sourceNaturalParts,
                                    fullText: pair.sourceText,
                                    count: count,
                                    compact: sourceCompact,
                                    language: sourceLanguage)
    let translatedParts = expandedParts(translatedNaturalParts,
                                        fullText: pair.translatedText,
                                        count: count,
                                        compact: targetCompact,
                                        language: targetLanguage)
    guard sourceParts.count == count, translatedParts.count == count else { return [pair] }
    let cleanedSourceParts = sourceParts.compactMap(removingEdgePunctuation)
    let cleanedTranslatedParts = translatedParts.compactMap(removingEdgePunctuation)
    guard cleanedSourceParts.count == count, cleanedTranslatedParts.count == count else { return [pair] }

    let weights = zip(cleanedSourceParts, cleanedTranslatedParts).map { source, translated in
      max(readingOptions.minimumSplitCueDuration,
          Double(readableCharacterCount(source)) / charactersPerSecond(sourceLanguage),
          Double(readableCharacterCount(translated)) / charactersPerSecond(targetLanguage))
    }
    let baselineDuration = readingOptions.minimumSplitCueDuration * Double(count)
    let distributableDuration = max(0, pair.timeRange.duration - baselineDuration)
    let totalWeight = weights.reduce(0, +)
    var cursor = pair.timeRange.start
    return cleanedSourceParts.indices.map { index in
      let end: Double
      if index == cleanedSourceParts.count - 1 {
        end = pair.timeRange.end
      } else {
        let proportional = totalWeight > 0
          ? distributableDuration * weights[index] / totalWeight
          : 0
        end = min(pair.timeRange.end,
                  cursor + readingOptions.minimumSplitCueDuration + proportional)
      }
      defer { cursor = end }
      return Pair(id: "\(pair.id)-display-\(index + 1)",
                  timeRange: AISubtitleTimeRange(start: cursor, end: end),
                  sourceText: cleanedSourceParts[index],
                  translatedText: cleanedTranslatedParts[index])
    }
  }

  private func expandedParts(_ naturalParts: [String],
                             fullText: String,
                             count: Int,
                             compact: Bool,
                             language: AISubtitleLanguage) -> [String] {
    guard naturalParts.count <= count else {
      return partitioner.balancedParts(fullText,
                                       count: count,
                                       compact: compact,
                                       language: language)
    }
    var result = naturalParts
    while result.count < count {
      let candidates = result.indices.sorted {
        partitioner.readableCharacterCount(result[$0])
          > partitioner.readableCharacterCount(result[$1])
      }
      var didSplit = false
      for index in candidates {
        let split = partitioner.balancedParts(result[index],
                                              count: 2,
                                              compact: compact,
                                              language: language)
        guard split.count == 2 else { continue }
        result.replaceSubrange(index...index, with: split)
        didSplit = true
        break
      }
      if !didSplit { break }
    }
    return result
  }

  private func readableDuration(sourceText: String,
                                sourceLanguage: AISubtitleLanguage,
                                translatedText: String,
                                targetLanguage: AISubtitleLanguage) -> Double {
    let source = Double(readableCharacterCount(sourceText)) / charactersPerSecond(sourceLanguage)
    let target = Double(readableCharacterCount(translatedText)) / charactersPerSecond(targetLanguage)
    return min(readingOptions.maximumDisplayDuration,
               max(readingOptions.minimumDisplayDuration, source, target))
  }

  private func charactersPerSecond(_ language: AISubtitleLanguage) -> Double {
    usesCompactWritingSystem(language)
      ? readingOptions.compactCharactersPerSecond
      : readingOptions.latinCharactersPerSecond
  }

  private func wrappedForDisplay(_ text: String, language: AISubtitleLanguage) -> String {
    let characters = Array(text.replacingOccurrences(of: "\n", with: " "))
    let lineLimit = usesCompactWritingSystem(language)
      ? readingOptions.compactLineCharacterCount
      : readingOptions.latinLineCharacterCount
    guard characters.count > lineLimit else { return text }

    let parts = partitioner.balancedLineParts(
      String(characters),
      maximumLineCharacterCount: lineLimit,
      compact: usesCompactWritingSystem(language),
      language: language)
    guard parts.count == 2 else { return text }
    let first = removingLineEndPunctuation(parts[0])
    let second = removingLineEndPunctuation(parts[1])
    guard !first.isEmpty, !second.isEmpty else { return text }
    return first + "\n" + second
  }

  private func removingLineEndPunctuation(_ text: String) -> String {
    var characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
    while let last = characters.last, Self.trailingPunctuation.contains(last) {
      characters.removeLast()
    }
    while characters.first?.isWhitespace == true { characters.removeFirst() }
    return String(characters)
  }

  private func normalizedSegment(_ segment: AISubtitleSegment) -> AISubtitleSegment? {
    let text = segment.text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !text.isEmpty, !segment.timeRange.isEmpty else { return nil }
    var normalized = segment
    normalized.text = text
    return normalized
  }

  private func removingEdgePunctuation(_ text: String) -> String? {
    var characters = Array(normalizedPunctuation(in: text)
      .trimmingCharacters(in: .whitespacesAndNewlines))
    while let first = characters.first, Self.trailingPunctuation.contains(first) {
      characters.removeFirst()
    }
    var closingSuffix: [Character] = []
    while let last = characters.last, Self.closingCharacters.contains(last) {
      closingSuffix.append(characters.removeLast())
    }
    while let last = characters.last, Self.trailingPunctuation.contains(last) {
      characters.removeLast()
    }
    characters.append(contentsOf: closingSuffix.reversed())
    let result = String(characters).trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
  }

  private func normalizedPunctuation(in text: String) -> String {
    let collapsible = Set("。！？!?.,，")
    let compactPunctuation = Set("。！？，、；：")
    var result: [Character] = []
    for character in text {
      if character.isWhitespace,
         let previous = result.last,
         compactPunctuation.contains(previous) {
        continue
      }
      if let previous = result.last,
         previous == character,
         collapsible.contains(character) {
        continue
      }
      result.append(character)
    }
    return String(result)
  }

  private func readableCharacterCount(_ text: String) -> Int {
    text.unicodeScalars.filter {
      !CharacterSet.whitespacesAndNewlines.contains($0)
        && !CharacterSet.punctuationCharacters.contains($0)
    }.count
  }

  private func usesCompactWritingSystem(_ language: AISubtitleLanguage) -> Bool {
    let primaryCode = language.code.replacingOccurrences(of: "_", with: "-")
      .lowercased()
      .split(separator: "-")
      .first
      .map(String.init)
    return primaryCode.map { ["zh", "ja", "ko"].contains($0) } ?? false
  }
}

enum AISubtitleFileFormat {
  case webVTT
  case srt
}

struct AISubtitleFileWriter {
  func string(for cues: [AISubtitleCue], format: AISubtitleFileFormat) -> String {
    switch format {
    case .webVTT:
      let body = cues.map(webVTTCue).joined(separator: "\n\n")
      return body.isEmpty ? "WEBVTT\n" : "WEBVTT\n\n\(body)\n"
    case .srt:
      let body = cues.enumerated().map { srtCue(index: $0.offset + 1, cue: $0.element) }
        .joined(separator: "\n\n")
      return body.isEmpty ? "" : "\(body)\n"
    }
  }

  private func webVTTCue(_ cue: AISubtitleCue) -> String {
    let start = timestamp(cue.timeRange.start, millisecondSeparator: ".")
    let end = timestamp(cue.timeRange.end, millisecondSeparator: ".")
    return "\(start) --> \(end)\n\(safePayload(cue.text))"
  }

  private func srtCue(index: Int, cue: AISubtitleCue) -> String {
    let start = timestamp(cue.timeRange.start, millisecondSeparator: ",")
    let end = timestamp(cue.timeRange.end, millisecondSeparator: ",")
    return "\(index)\n\(start) --> \(end)\n\(safePayload(cue.text))"
  }

  private func timestamp(_ seconds: Double, millisecondSeparator: Character) -> String {
    let totalMilliseconds = Int64((max(0, seconds) * 1000).rounded())
    let milliseconds = totalMilliseconds % 1000
    let totalSeconds = totalMilliseconds / 1000
    let second = totalSeconds % 60
    let totalMinutes = totalSeconds / 60
    let minute = totalMinutes % 60
    let hour = totalMinutes / 60
    return String(format: "%02lld:%02lld:%02lld%c%03lld",
                  hour, minute, second, millisecondSeparator.asciiValue ?? 46, milliseconds)
  }

  private func safePayload(_ text: String) -> String {
    text.replacingOccurrences(of: "\0", with: "")
      .replacingOccurrences(of: "-->", with: "--\u{200B}>")
  }
}

struct AISubtitleCacheMetadata: Codable, Hashable {
  static let currentSchemaVersion = 12

  var schemaVersion: Int
  var key: AISubtitleCacheKey
  var createdAt: Date
  var updatedAt: Date
  var coveredRanges: [AISubtitleTimeRange]
  var transcriptSegmentCount: Int
  var cueCount: Int

  init(key: AISubtitleCacheKey,
       createdAt: Date = Date(),
       updatedAt: Date = Date(),
       coveredRanges: [AISubtitleTimeRange],
       transcriptSegmentCount: Int,
       cueCount: Int,
       schemaVersion: Int = AISubtitleCacheMetadata.currentSchemaVersion) {
    self.schemaVersion = schemaVersion
    self.key = key
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.coveredRanges = coveredRanges
    self.transcriptSegmentCount = transcriptSegmentCount
    self.cueCount = cueCount
  }
}

struct AISubtitleCachePolicy {
  static let maximumBytesDefaultsKey = "aiSubtitle.cacheMaximumBytes"
  static let defaultMaximumBytes: Int64 = 2 * 1024 * 1024 * 1024

  var maximumBytes: Int64

  init(maximumBytes: Int64 = (UserDefaults.standard.object(forKey: maximumBytesDefaultsKey) as? NSNumber)?.int64Value
    ?? defaultMaximumBytes) {
    self.maximumBytes = max(0, maximumBytes)
  }
}

struct AISubtitleCacheUsage: Hashable {
  var totalBytes: Int64
  var entryCount: Int
  var removedBytes: Int64
  var removedEntryCount: Int
}

struct AISubtitleCacheStore {
  var layout: AISubtitleCacheLayout
  var fileManager: FileManager = .default
  private let writer = AISubtitleFileWriter()

  init(layout: AISubtitleCacheLayout = AISubtitleCacheLayout(),
       fileManager: FileManager = .default) {
    self.layout = layout
    self.fileManager = fileManager
  }

  @discardableResult
  func save(transcript: [AISubtitleSegment],
            cues: [AISubtitleCue],
            coveredRanges: [AISubtitleTimeRange],
            for key: AISubtitleCacheKey,
            now: Date = Date()) throws -> AISubtitleCacheArtifacts {
    let artifacts = try layout.artifacts(for: key, createDirectories: true)
    let existingMetadata = try? metadata(for: key)
    let sourceLanguage = AISubtitleLanguage(key.sourceLanguageCode ?? "und")
    let targetLanguage = AISubtitleLanguage(key.targetLanguageCode)
    let timeline = AISubtitlePairedTimelineAssembler().assemble(
      transcript: transcript,
      translatedCues: cues,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage)
    let metadata = AISubtitleCacheMetadata(key: key,
                                           createdAt: existingMetadata?.createdAt ?? now,
                                           updatedAt: now,
                                           coveredRanges: coveredRanges,
                                           transcriptSegmentCount: timeline.transcript.count,
                                           cueCount: timeline.translatedCues.count)

    // Keep resumable cache data semantic. Display splitting is derived for exports only;
    // persisting it would split the same cues again whenever a task resumes.
    try encodedData(transcript).write(to: artifacts.transcriptURL, options: .atomic)
    try encodedData(cues).write(to: artifacts.translatedCuesURL, options: .atomic)
    try writer.string(for: timeline.originalCues, format: .webVTT)
      .write(to: artifacts.originalVTTURL, atomically: true, encoding: .utf8)
    try writer.string(for: timeline.originalCues, format: .srt)
      .write(to: artifacts.originalSRTURL, atomically: true, encoding: .utf8)
    try writer.string(for: timeline.translatedCues, format: .webVTT)
      .write(to: artifacts.translatedVTTURL, atomically: true, encoding: .utf8)
    try writer.string(for: timeline.translatedCues, format: .srt)
      .write(to: artifacts.translatedSRTURL, atomically: true, encoding: .utf8)
    // Metadata is the commit marker. Readers only accept a cache after this write succeeds.
    try encodedData(metadata).write(to: artifacts.metadataURL, options: .atomic)
    _ = try? prune(maximumBytes: AISubtitleCachePolicy().maximumBytes, excluding: key)
    return artifacts
  }

  func metadata(for key: AISubtitleCacheKey) throws -> AISubtitleCacheMetadata {
    let artifacts = try layout.artifacts(for: key)
    let data = try Data(contentsOf: artifacts.metadataURL)
    return try decoder().decode(AISubtitleCacheMetadata.self, from: data)
  }

  func cachedContent(for key: AISubtitleCacheKey) throws -> (metadata: AISubtitleCacheMetadata,
                                                              transcript: [AISubtitleSegment],
                                                              cues: [AISubtitleCue]) {
    let artifacts = try layout.artifacts(for: key)
    let metadata = try self.metadata(for: key)
    guard metadata.schemaVersion == AISubtitleCacheMetadata.currentSchemaVersion,
          metadata.key.stableIdentifier == key.stableIdentifier else {
      throw AISubtitleError(code: "cache_schema_mismatch",
                            message: "The AI subtitle cache was created by an incompatible schema.")
    }
    let transcript = try decoder().decode([AISubtitleSegment].self,
                                          from: Data(contentsOf: artifacts.transcriptURL))
    let cues = try decoder().decode([AISubtitleCue].self,
                                    from: Data(contentsOf: artifacts.translatedCuesURL))
    return (metadata, transcript, cues)
  }

  func cachedVTT(for key: AISubtitleCacheKey) -> URL? {
    cachedArtifacts(for: key)?.translatedVTTURL
  }

  func cachedArtifacts(for key: AISubtitleCacheKey) -> AISubtitleCacheArtifacts? {
    guard let artifacts = try? layout.artifacts(for: key),
          fileManager.fileExists(atPath: artifacts.metadataURL.path),
          fileManager.fileExists(atPath: artifacts.translatedCuesURL.path),
          fileManager.fileExists(atPath: artifacts.originalVTTURL.path),
          fileManager.fileExists(atPath: artifacts.originalSRTURL.path),
          fileManager.fileExists(atPath: artifacts.translatedVTTURL.path),
          fileManager.fileExists(atPath: artifacts.translatedSRTURL.path),
          (try? cachedContent(for: key)) != nil else {
      return nil
    }
    return artifacts
  }

  func removeCachedContent(for key: AISubtitleCacheKey) throws {
    let directoryURL = try layout.artifacts(for: key).directoryURL
    guard fileManager.fileExists(atPath: directoryURL.path) else { return }
    try fileManager.removeItem(at: directoryURL)
  }

  @discardableResult
  func refreshSubtitleFiles(for key: AISubtitleCacheKey) throws -> AISubtitleCacheArtifacts {
    let cached = try cachedContent(for: key)
    return try save(transcript: cached.transcript,
                    cues: cached.cues,
                    coveredRanges: cached.metadata.coveredRanges,
                    for: key)
  }

  func completionProgress(for key: AISubtitleCacheKey, mediaDuration: Double) -> Double {
    guard mediaDuration > 0,
          let metadata = try? self.metadata(for: key),
          metadata.schemaVersion == AISubtitleCacheMetadata.currentSchemaVersion,
          metadata.key.stableIdentifier == key.stableIdentifier else {
      return 0
    }
    let coveredDuration = boundedMergedRanges(metadata.coveredRanges,
                                              mediaDuration: mediaDuration).reduce(0) { $0 + $1.duration }
    return min(1, coveredDuration / mediaDuration)
  }

  func isComplete(for key: AISubtitleCacheKey, mediaDuration: Double) -> Bool {
    guard mediaDuration > 0,
          let metadata = try? self.metadata(for: key),
          metadata.schemaVersion == AISubtitleCacheMetadata.currentSchemaVersion,
          metadata.key.stableIdentifier == key.stableIdentifier else { return false }
    let ranges = boundedMergedRanges(metadata.coveredRanges, mediaDuration: mediaDuration)
    guard ranges.count == 1, let range = ranges.first else { return false }
    return range.start <= 0.01 && range.end >= mediaDuration - 0.01
  }

  func usage() throws -> AISubtitleCacheUsage {
    let entries = try cacheEntries()
    return AISubtitleCacheUsage(totalBytes: entries.reduce(0) { $0 + $1.byteCount },
                                entryCount: entries.count,
                                removedBytes: 0,
                                removedEntryCount: 0)
  }

  @discardableResult
  func prune(maximumBytes: Int64,
             excluding protectedKey: AISubtitleCacheKey? = nil) throws -> AISubtitleCacheUsage {
    var entries = try cacheEntries()
    var totalBytes = entries.reduce(0) { $0 + $1.byteCount }
    let protectedDirectoryName = protectedKey?.stableIdentifier
    var removedBytes: Int64 = 0
    var removedEntryCount = 0

    entries.sort { $0.updatedAt < $1.updatedAt }
    for entry in entries where totalBytes > max(0, maximumBytes) {
      guard entry.url.lastPathComponent != protectedDirectoryName else { continue }
      try fileManager.removeItem(at: entry.url)
      totalBytes -= entry.byteCount
      removedBytes += entry.byteCount
      removedEntryCount += 1
    }
    return AISubtitleCacheUsage(totalBytes: totalBytes,
                                entryCount: entries.count - removedEntryCount,
                                removedBytes: removedBytes,
                                removedEntryCount: removedEntryCount)
  }

  private func cacheEntries() throws -> [(url: URL, byteCount: Int64, updatedAt: Date)] {
    guard fileManager.fileExists(atPath: layout.rootURL.path) else { return [] }
    let directories = try fileManager.contentsOfDirectory(at: layout.rootURL,
                                                           includingPropertiesForKeys: [.isDirectoryKey],
                                                           options: [.skipsHiddenFiles])
    return try directories.compactMap { directoryURL in
      let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
      guard values.isDirectory == true else { return nil }
      let metadataURL = directoryURL.appendingPathComponent("metadata.json")
      let updatedAt = (try? decodedMetadata(at: metadataURL).updatedAt)
        ?? (try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      return (directoryURL, try directoryByteCount(directoryURL), updatedAt)
    }
  }

  private func decodedMetadata(at url: URL) throws -> AISubtitleCacheMetadata {
    try decoder().decode(AISubtitleCacheMetadata.self, from: Data(contentsOf: url))
  }

  private func directoryByteCount(_ directoryURL: URL) throws -> Int64 {
    guard let enumerator = fileManager.enumerator(at: directoryURL,
                                                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                  options: [.skipsHiddenFiles]) else { return 0 }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      if values.isRegularFile == true {
        total += Int64(values.fileSize ?? 0)
      }
    }
    return total
  }

  private func encodedData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(value)
  }

  private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }

  private func boundedMergedRanges(_ ranges: [AISubtitleTimeRange],
                                   mediaDuration: Double) -> [AISubtitleTimeRange] {
    var result: [AISubtitleTimeRange] = []
    let boundedRanges = ranges.map {
      AISubtitleTimeRange(start: min(mediaDuration, max(0, $0.start)),
                          end: min(mediaDuration, max(0, $0.end)))
    }
    for range in boundedRanges.sorted(by: { $0.start < $1.start }) where !range.isEmpty {
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
}

struct AISubtitleSidecarFiles: Hashable {
  var originalURL: URL
  var translatedURL: URL?

  var allURLs: [URL] {
    [originalURL] + [translatedURL].compactMap { $0 }
  }
}

struct AISubtitleSidecarPublisher {
  var fileManager: FileManager = .default

  func destinations(key: AISubtitleCacheKey, mediaURL: URL) throws -> AISubtitleSidecarFiles {
    guard mediaURL.isFileURL else {
      throw AISubtitleError(code: "sidecar_requires_local_media",
                            message: "AI subtitle files can only be saved beside a local video.")
    }
    let directoryURL = mediaURL.deletingLastPathComponent()
    let baseName = mediaURL.deletingPathExtension().lastPathComponent
    let sourceCode = safeLanguageCode(key.sourceLanguageCode ?? "und")
    let targetCode = safeLanguageCode(key.targetLanguageCode)
    let originalURL = directoryURL
      .appendingPathComponent("\(baseName).rawya-ai.\(sourceCode).srt", isDirectory: false)
    let sourceLanguage = AISubtitleLanguage(key.sourceLanguageCode ?? "und")
    let targetLanguage = AISubtitleLanguage(key.targetLanguageCode)
    let translatedURL = sourceLanguage.isEquivalent(to: targetLanguage)
      ? nil
      : directoryURL.appendingPathComponent("\(baseName).rawya-ai.\(targetCode).srt", isDirectory: false)
    return AISubtitleSidecarFiles(originalURL: originalURL, translatedURL: translatedURL)
  }

  func publish(artifacts: AISubtitleCacheArtifacts,
               key: AISubtitleCacheKey,
               mediaURL: URL) throws -> AISubtitleSidecarFiles {
    let files = try destinations(key: key, mediaURL: mediaURL)
    let directoryURL = mediaURL.deletingLastPathComponent()
    guard fileManager.isWritableFile(atPath: directoryURL.path) else {
      throw AISubtitleError(code: "sidecar_directory_not_writable",
                            message: "The video folder is not writable. AI subtitles remain available in the app cache.")
    }

    let sourceLanguage = AISubtitleLanguage(key.sourceLanguageCode ?? "und")
    let targetLanguage = AISubtitleLanguage(key.targetLanguageCode)
    let translationRequired = !sourceLanguage.isEquivalent(to: targetLanguage)
    guard hasSubtitleContent(at: artifacts.originalSRTURL),
          !translationRequired || hasSubtitleContent(at: artifacts.translatedSRTURL) else {
      throw AISubtitleError(code: "empty_subtitle_result",
                            message: "No dialogue was recognized, so no subtitle files were saved.")
    }

    try copyAtomically(from: artifacts.originalSRTURL, to: files.originalURL)

    guard translationRequired else {
      return files
    }

    guard let translatedURL = files.translatedURL else { return files }
    try copyAtomically(from: artifacts.translatedSRTURL, to: translatedURL)
    return files
  }

  private func safeLanguageCode(_ code: String) -> String {
    let normalized = code.replacingOccurrences(of: "_", with: "-").lowercased()
    let filtered = normalized.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    return filtered.isEmpty ? "und" : filtered
  }

  private func copyAtomically(from sourceURL: URL, to destinationURL: URL) throws {
    let data = try Data(contentsOf: sourceURL)
    try data.write(to: destinationURL, options: .atomic)
  }

  private func hasSubtitleContent(at url: URL) -> Bool {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
    return size > 0
  }
}

struct AISubtitleFilePipeline {
  var cacheStore = AISubtitleCacheStore()

  func prepare(transcript: [AISubtitleSegment],
               targetLanguage: AISubtitleLanguage,
               cacheKey: AISubtitleCacheKey) throws -> AISubtitleCacheArtifacts {
    let cues = transcript.map {
      AISubtitleCue(id: $0.id,
                    timeRange: $0.timeRange,
                    text: $0.text,
                    language: targetLanguage)
    }
    guard !transcript.isEmpty else {
      throw AISubtitleError(code: "empty_transcript",
                            message: "The transcript does not contain any timed subtitle text.")
    }
    return try cacheStore.save(transcript: transcript,
                               cues: cues,
                               coveredRanges: coveredRanges(for: cues),
                               for: cacheKey)
  }

  func prepare(transcriptURL: URL,
               targetLanguage: AISubtitleLanguage,
               cacheKey: AISubtitleCacheKey) throws -> AISubtitleCacheArtifacts {
    let data = try Data(contentsOf: transcriptURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let transcript = try decoder.decode([AISubtitleSegment].self, from: data)
    return try prepare(transcript: transcript,
                       targetLanguage: targetLanguage,
                       cacheKey: cacheKey)
  }

  private func coveredRanges(for cues: [AISubtitleCue]) -> [AISubtitleTimeRange] {
    guard let first = cues.first else { return [] }
    var ranges = [first.timeRange]
    for cue in cues.dropFirst() {
      var last = ranges.removeLast()
      if cue.timeRange.start <= last.end + 1 {
        last.end = max(last.end, cue.timeRange.end)
        ranges.append(last)
      } else {
        ranges.append(last)
        ranges.append(cue.timeRange)
      }
    }
    return ranges
  }
}

final class AISubtitleFileLoader {
  private let minimumReloadInterval: TimeInterval
  private var loadedURL: URL?
  private var lastLoadAt: Date?
  private var pendingReload: DispatchWorkItem?

  init(minimumReloadInterval: TimeInterval = 2) {
    self.minimumReloadInterval = minimumReloadInterval
  }

  func update(url: URL, load: @escaping (URL) -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let now = Date()
      let isNewFile = self.loadedURL?.standardizedFileURL != url.standardizedFileURL
      let elapsed = now.timeIntervalSince(self.lastLoadAt ?? .distantPast)
      if isNewFile || elapsed >= self.minimumReloadInterval {
        self.performLoad(url: url, load: load)
        return
      }

      self.pendingReload?.cancel()
      let workItem = DispatchWorkItem { [weak self] in
        self?.performLoad(url: url, load: load)
      }
      self.pendingReload = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + self.minimumReloadInterval - elapsed,
                                    execute: workItem)
    }
  }

  func reset() {
    DispatchQueue.main.async { [weak self] in
      self?.pendingReload?.cancel()
      self?.pendingReload = nil
      self?.loadedURL = nil
      self?.lastLoadAt = nil
    }
  }

  private func performLoad(url: URL, load: (URL) -> Void) {
    pendingReload?.cancel()
    pendingReload = nil
    loadedURL = url
    lastLoadAt = Date()
    load(url)
  }
}
