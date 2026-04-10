import Foundation

// MARK: - Request

/// A request sent from the CLI to the daemon over the Unix socket.
public struct LocalRPCRequest: Codable, Sendable {
  public let id: String
  public let method: String
  public let params: JSONValue?

  public init(id: String = UUID().uuidString, method: String, params: JSONValue? = nil) {
    self.id = id
    self.method = method
    self.params = params
  }
}

// MARK: - Response

/// A response sent from the daemon back to the CLI.
public struct LocalRPCResponse: Codable, Sendable {
  public let id: String
  public let ok: Bool
  public let result: JSONValue?
  public let error: LocalRPCError?

  public static func success(id: String, result: JSONValue) -> LocalRPCResponse {
    LocalRPCResponse(id: id, ok: true, result: result, error: nil)
  }

  public static func failure(id: String, message: String) -> LocalRPCResponse {
    LocalRPCResponse(id: id, ok: false, result: nil, error: LocalRPCError(message: message))
  }
}

public struct LocalRPCError: Codable, Sendable {
  public let message: String

  public init(message: String) {
    self.message = message
  }
}

// MARK: - Well-known methods

public enum LocalRPCMethod {
  public static let status = "status"
  public static let stop = "stop"
  public static let restart = "restart"
  public static let callTool = "callTool"
  public static let tools = "tools"
  public static let toolSchema = "toolSchema"
}

// MARK: - callTool params

/// Parameters for a `callTool` request.
public struct CallToolParams: Codable, Sendable {
  public let tool: String
  public let arguments: JSONValue

  public init(tool: String, arguments: JSONValue = [:]) {
    self.tool = tool
    self.arguments = arguments
  }
}
