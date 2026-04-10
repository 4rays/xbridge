import Foundation

public enum XhammerError: Error, Sendable {
  case daemonNotRunning
  case connectionFailed(String)
  case bridgeNotRunning
  case bridgeTimeout
  case mcpError(code: Int, message: String)
  case decodingError(String)
  case toolNotFound(String)
  case invalidResponse(String)
  case socketError(String)
  case writeFailed
}

extension XhammerError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .daemonNotRunning:
      return "xhammerd is not running"
    case .connectionFailed(let msg):
      return "Connection to daemon failed: \(msg)"
    case .bridgeNotRunning:
      return "Xcode MCP bridge is not running"
    case .bridgeTimeout:
      return "Request to Xcode timed out"
    case .mcpError(_, let message):
      return "Xcode error: \(message)"
    case .decodingError(let msg):
      return "Failed to decode response: \(msg)"
    case .toolNotFound(let name):
      return "Tool not found: \(name)"
    case .invalidResponse(let msg):
      return "Invalid response: \(msg)"
    case .socketError(let msg):
      return "Socket error: \(msg)"
    case .writeFailed:
      return "Failed to write to bridge"
    }
  }
}
