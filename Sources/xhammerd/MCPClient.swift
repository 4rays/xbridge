import Foundation
import XhammerCore

/// Implements the minimal MCP protocol needed to talk to xcrun mcpbridge.
actor MCPClient {
  private let bridge: BridgeProcess
  private let logger: Logger
  private(set) var knownTools: [MCPTool] = []
  private(set) var isInitialized = false

  init(bridge: BridgeProcess, logger: Logger) {
    self.bridge = bridge
    self.logger = logger
  }

  // MARK: - Lifecycle

  func start() async throws {
    try await bridge.start()
    try await initialize()
    knownTools = try await listTools()
    logger.info("MCP ready — \(knownTools.count) tools discovered")
  }

  func stop() async {
    await bridge.stop()
    isInitialized = false
    knownTools = []
  }

  // MARK: - MCP initialization

  private func initialize() async throws {
    let params = MCPInitializeParams()
    let paramsData = try JSONEncoder().encode(params)
    let paramsJSON = try JSONDecoder().decode(JSONValue.self, from: paramsData)

    let id = await bridge.nextID()
    let request = MCPRequest(id: id, method: "initialize", params: paramsJSON)
    let response = try await bridge.send(request)

    if let err = response.error {
      throw XhammerError.mcpError(code: err.code, message: err.message)
    }

    // Send initialized notification (no response expected)
    let notif = MCPNotification(method: "notifications/initialized")
    let notifData = try JSONEncoder().encode(notif)
    if let line = String(data: notifData, encoding: .utf8) {
      try await bridge.sendRaw(line)
    }

    isInitialized = true
    logger.info("MCP session initialized")
  }

  // MARK: - tools/list

  private func listTools() async throws -> [MCPTool] {
    let id = await bridge.nextID()
    let request = MCPRequest(id: id, method: "tools/list", params: [:])
    let response = try await bridge.send(request)

    if let err = response.error {
      throw XhammerError.mcpError(code: err.code, message: err.message)
    }
    guard let result = response.result else {
      throw XhammerError.invalidResponse("tools/list returned no result")
    }

    let resultData = try JSONEncoder().encode(result)
    let toolsList = try JSONDecoder().decode(MCPToolsListResult.self, from: resultData)
    return toolsList.tools
  }

  // MARK: - tools/call

  /// Call a named MCP tool and return the result as JSONValue.
  func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
    let id = await bridge.nextID()
    let params: JSONValue = [
      "name": .string(name),
      "arguments": arguments
    ]
    let request = MCPRequest(id: id, method: "tools/call", params: params)
    let response = try await bridge.send(request)

    if let err = response.error {
      throw XhammerError.mcpError(code: err.code, message: err.message)
    }
    guard let result = response.result else {
      throw XhammerError.invalidResponse("tools/call returned no result")
    }

    // Check for tool-level errors (isError: true in result)
    let resultData = try JSONEncoder().encode(result)
    if let callResult = try? JSONDecoder().decode(MCPToolCallResult.self, from: resultData),
      callResult.isError == true
    {
      let msg = callResult.content.compactMap(\.text).joined(separator: "\n")
      throw XhammerError.mcpError(code: -1, message: msg.isEmpty ? "Tool call failed" : msg)
    }

    return result
  }

  // MARK: - Restart

  func restart() async throws {
    logger.info("Restarting bridge...")
    await bridge.stop()
    isInitialized = false
    knownTools = []
    try await start()
  }
}
