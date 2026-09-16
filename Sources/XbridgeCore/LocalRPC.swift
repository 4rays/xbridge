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

  public static func failure(id: String, code: String, message: String) -> LocalRPCResponse {
    LocalRPCResponse(id: id, ok: false, result: nil, error: LocalRPCError(code: code, message: message))
  }
}

public struct LocalRPCError: Codable, Sendable {
  public let code: String?
  public let message: String

  public init(code: String? = nil, message: String) {
    self.code = code
    self.message = message
  }
}

// MARK: - Well-known methods

public enum LocalRPCMethod {
  public static let status = "status"
  public static let stop = "stop"
  public static let relink = "relink"
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

  /// Tools that reject `workspaceIdentifier` (no such property, or a different required id).
  public static let toolsWithoutWorkspaceIdentifier: Set<String> = [
    XcodeTool.listWorkspaces,
    XcodeTool.openWorkspace,
    XcodeTool.newProject,
    XcodeTool.documentationSearch,
    XcodeTool.deviceInteractionStartSession,
    XcodeTool.deviceInteractionEndSession,
    XcodeTool.deviceInteractionSynthesize
  ]

  public func injectingWorkspace(_ workspace: String?) -> CallToolParams {
    guard let workspace, !workspace.isEmpty else { return self }
    guard !Self.toolsWithoutWorkspaceIdentifier.contains(tool) else { return self }
    guard var object = arguments.objectValue else { return self }
    if object["workspaceIdentifier"] == nil {
      object["workspaceIdentifier"] = .string(workspace)
    }
    return CallToolParams(tool: tool, arguments: .object(object))
  }
}
