import Foundation

// FileHandle.write(_:) is documented as thread-safe.
public struct Logger: @unchecked Sendable {
  public enum Level: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: Level, rhs: Level) -> Bool {
      lhs.rawValue < rhs.rawValue
    }

    var prefix: String {
      switch self {
      case .debug: return "DEBUG"
      case .info: return "INFO"
      case .warning: return "WARN"
      case .error: return "ERROR"
      }
    }
  }

  private let label: String
  private let fileHandle: FileHandle
  public let minimumLevel: Level

  public static let stderr = Logger(label: "xhammer", fileHandle: .standardError)

  public init(label: String, fileHandle: FileHandle = .standardError, minimumLevel: Level = .info) {
    self.label = label
    self.fileHandle = fileHandle
    self.minimumLevel = minimumLevel
  }

  public func log(_ level: Level, _ message: String) {
    guard level >= minimumLevel else { return }
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "\(ts) [\(level.prefix)] [\(label)] \(message)\n"
    if let data = line.data(using: .utf8) {
      fileHandle.write(data)
    }
  }

  public func debug(_ message: String) { log(.debug, message) }
  public func info(_ message: String) { log(.info, message) }
  public func warning(_ message: String) { log(.warning, message) }
  public func error(_ message: String) { log(.error, message) }
}
