import Foundation

enum Utility {
  static let cacheURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
  static let binariesURL = cacheURL
  static let exeDirURL = cacheURL
  static let appSupportDirUrl = cacheURL
}

final class KeychainAccess {
  struct ServiceName: RawRepresentable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
  }

  static func read(username: String?, forService: ServiceName) throws -> (username: String, password: String) {
    throw NSError(domain: "rawya-ai-subtitle-evaluation", code: 1)
  }

  static func write(username: String, password: String, forService: ServiceName) throws {}
  static func delete(username: String? = nil, forService: ServiceName) throws {}
}

final class FFmpegController {
  static func extractAudio(from sourceURL: URL,
                           streamIndex: Int,
                           startTime: TimeInterval,
                           duration: TimeInterval,
                           outputURL: URL) throws {
    try extractAudio(from: sourceURL,
                     streamIndex: streamIndex,
                     startTime: startTime,
                     duration: duration,
                     outputURL: outputURL,
                     shouldCancel: { false })
  }

  static func extractAudio(from sourceURL: URL,
                           streamIndex: Int,
                           startTime: TimeInterval,
                           duration: TimeInterval,
                           outputURL: URL,
                           shouldCancel: () -> Bool) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    let arguments = [
      "-hide_banner", "-loglevel", "error", "-y",
      "-ss", String(format: "%.3f", startTime),
      "-i", sourceURL.path,
      "-t", String(format: "%.3f", duration),
      "-map", streamIndex >= 0 ? "0:\(streamIndex)" : "0:a:0",
      "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
      outputURL.path
    ]
    process.arguments = arguments
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    while process.isRunning {
      if shouldCancel() {
        process.terminate()
        throw AISubtitleError(code: "audio_extraction_canceled",
                              message: "Audio extraction was canceled.")
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
      let message = String(data: errorData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw NSError(domain: "rawya-ai-subtitle-evaluation.ffmpeg",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "ffmpeg failed"])
    }
  }
}
