import Darwin
import Foundation

public actor LocalTraceWriter: AgentTracing {
  public nonisolated let directory: String?
  private let directoryURL: URL
  private var sequence = 0
  private let encoder: JSONEncoder

  public init(directory: String? = nil, now: Date = Date()) throws {
    let root: URL
    if let directory {
      root = URL(fileURLWithPath: directory, isDirectory: true)
    } else {
      root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
          "Library/Application Support/xbridge/device-agent-runs", isDirectory: true
        )
        .appendingPathComponent(Self.timestamp(now), isDirectory: true)
    }
    do {
      try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      guard Darwin.chmod(root.path, 0o700) == 0 else {
        throw AgentError.trace("Failed to set owner-only permissions on \(root.path)")
      }
    } catch let error as AgentError {
      throw error
    } catch {
      throw AgentError.trace("Failed to create trace directory: \(error.localizedDescription)")
    }
    self.directoryURL = root
    self.directory = root.path
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder.dateEncodingStrategy = .iso8601
  }

  public func record<Value: Encodable & Sendable>(_ name: String, value: Value) async throws {
    sequence += 1
    let safeName = name.replacingOccurrences(of: "/", with: "-")
    let url = directoryURL.appendingPathComponent(
      String(format: "%03d-%@.json", sequence, safeName))
    do {
      let data = try encoder.encode(value)
      try data.write(to: url, options: .atomic)
      guard Darwin.chmod(url.path, 0o600) == 0 else {
        throw AgentError.trace("Failed to protect trace file \(url.path)")
      }
    } catch let error as AgentError {
      throw error
    } catch {
      throw AgentError.trace("Failed to write trace event: \(error.localizedDescription)")
    }
  }

  public func copyArtifact(at path: String, name: String) async throws {
    let source = URL(fileURLWithPath: path)
    guard FileManager.default.isReadableFile(atPath: source.path) else { return }
    let extensionPart = source.pathExtension.isEmpty ? "" : ".\(source.pathExtension)"
    let destination = directoryURL.appendingPathComponent("\(name)\(extensionPart)")
    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: source, to: destination)
      guard Darwin.chmod(destination.path, 0o600) == 0 else {
        throw AgentError.trace("Failed to protect copied artifact \(destination.path)")
      }
    } catch let error as AgentError {
      throw error
    } catch {
      throw AgentError.trace("Failed to copy Device Hub artifact: \(error.localizedDescription)")
    }
  }

  private static func timestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return formatter.string(from: date)
  }
}

public struct NullTraceWriter: AgentTracing {
  public let directory: String? = nil
  public init() {}
  public func record<Value: Encodable & Sendable>(_ name: String, value: Value) async throws {}
  public func copyArtifact(at path: String, name: String) async throws {}
}
