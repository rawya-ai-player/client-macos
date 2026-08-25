#!/usr/bin/env swift

import AppKit
import Foundation
import Vision

struct OCRCue {
  var start: Double
  var end: Double
  var text: String
}

enum OCRFailure: Error, CustomStringConvertible {
  case usage
  case unreadableImage(String)

  var description: String {
    switch self {
    case .usage:
      return "Usage: extract_burned_subtitle_reference.swift <frames-dir> <frames-per-second> <language> <output.srt>"
    case .unreadableImage(let path):
      return "Could not read OCR frame: \(path)"
    }
  }
}

func normalized(_ text: String) -> String {
  text.unicodeScalars.filter {
    CharacterSet.alphanumerics.contains($0)
  }.map(String.init).joined().lowercased()
}

func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
  guard !lhs.isEmpty else { return rhs.count }
  guard !rhs.isEmpty else { return lhs.count }
  var previous = Array(0...rhs.count)
  for (leftIndex, left) in lhs.enumerated() {
    var current = Array(repeating: 0, count: rhs.count + 1)
    current[0] = leftIndex + 1
    for (rightIndex, right) in rhs.enumerated() {
      current[rightIndex + 1] = min(
        previous[rightIndex + 1] + 1,
        current[rightIndex] + 1,
        previous[rightIndex] + (left == right ? 0 : 1))
    }
    previous = current
  }
  return previous[rhs.count]
}

func similarity(_ lhs: String, _ rhs: String) -> Double {
  let left = Array(normalized(lhs))
  let right = Array(normalized(rhs))
  let maximum = max(left.count, right.count)
  guard maximum > 0 else { return 1 }
  return 1 - Double(editDistance(left, right)) / Double(maximum)
}

func recognizedText(at url: URL, language: String) throws -> String? {
  guard let image = NSImage(contentsOf: url),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    throw OCRFailure.unreadableImage(url.path)
  }
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.recognitionLanguages = [language]
  request.usesLanguageCorrection = true
  try VNImageRequestHandler(cgImage: cgImage).perform([request])
  let observations = (request.results ?? []).filter {
    let box = $0.boundingBox
    return box.midX >= 0.2 && box.midX <= 0.8 && box.width >= 0.08
  }.sorted {
    if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.08 {
      return $0.boundingBox.midY > $1.boundingBox.midY
    }
    return $0.boundingBox.minX < $1.boundingBox.minX
  }
  let lines = observations.compactMap { $0.topCandidates(1).first?.string }
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  guard !lines.isEmpty else { return nil }
  return lines.joined(separator: " ")
}

func timestamp(_ seconds: Double) -> String {
  let totalMilliseconds = Int64((max(0, seconds) * 1000).rounded())
  let milliseconds = totalMilliseconds % 1000
  let totalSeconds = totalMilliseconds / 1000
  return String(format: "%02lld:%02lld:%02lld,%03lld",
                totalSeconds / 3600,
                totalSeconds / 60 % 60,
                totalSeconds % 60,
                milliseconds)
}

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard arguments.count == 4,
        let framesPerSecond = Double(arguments[1]),
        framesPerSecond > 0 else { throw OCRFailure.usage }
  let directory = URL(fileURLWithPath: arguments[0], isDirectory: true)
  let language = arguments[2]
  let outputURL = URL(fileURLWithPath: arguments[3])
  let frames = try FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles])
    .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

  var cues: [OCRCue] = []
  var active: OCRCue?
  var activeSamples = 0
  for (offset, frame) in frames.enumerated() {
    let start = Double(offset) / framesPerSecond
    let end = Double(offset + 1) / framesPerSecond
    let text = try recognizedText(at: frame, language: language)
    if let text, !normalized(text).isEmpty {
      if var current = active, similarity(current.text, text) >= 0.82 {
        current.end = end
        if normalized(text).count > normalized(current.text).count { current.text = text }
        active = current
        activeSamples += 1
      } else {
        if let current = active, activeSamples >= 2 { cues.append(current) }
        active = OCRCue(start: start, end: end, text: text)
        activeSamples = 1
      }
    } else {
      if let current = active, activeSamples >= 2 { cues.append(current) }
      active = nil
      activeSamples = 0
    }
    if (offset + 1) % 100 == 0 {
      print("ocr=\(offset + 1)/\(frames.count)")
      fflush(stdout)
    }
  }
  if let current = active, activeSamples >= 2 { cues.append(current) }

  let srt = cues.enumerated().map { index, cue in
    "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)"
  }.joined(separator: "\n\n") + (cues.isEmpty ? "" : "\n")
  try srt.write(to: outputURL, atomically: true, encoding: .utf8)
  print("cues=\(cues.count)")
  print(outputURL.path)
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
