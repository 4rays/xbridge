import Foundation
import XbridgeCore

/// Implements the minimal MCP protocol needed to talk to xcrun mcpbridge.
actor MCPClient {
  enum LinkState: Sendable {
    case down
    case linking
    case ready
    case awaitingGrant
  }

  private let bridge: BridgeProcess
  private let logger: Logger
  private(set) var knownTools: [MCPTool] = []
  private(set) var linkState: LinkState = .down
  private var consecutiveHandshakeFailures = 0
  private var isRespawning = false

  init(bridge: BridgeProcess, logger: Logger) {
    self.bridge = bridge
    self.logger = logger
  }

  // MARK: - Lifecycle

  func start() async {
    linkState = .linking
    do {
      try await bridge.start()
      try await runHandshake()
      linkState = .ready
    } catch {
      linkState = .down
      logger.warning("MCP start failed: \(error.localizedDescription) — will retry on first call")
    }
  }

  func stop() async {
    await bridge.stop()
    linkState = .down
    knownTools = []
  }

  // MARK: - Probe (for status — calls a real Xcode tool)

  func probe() async -> LinkState {
    guard case .ready = linkState else { return linkState }
    let id = await bridge.nextID()
    let params: JSONValue = [
      "name": .string("XcodeListWindows"),
      "arguments": .object([:])
    ]
    let request = MCPRequest(id: id, method: "tools/call", params: params)
    do {
      let response = try await bridge.send(request)
      if response.error != nil { return .down }
      return .ready
    } catch {
      let cause = await bridge.lastTerminationCause
      if cause == .duringToolCall {
        linkState = .awaitingGrant
        return .awaitingGrant
      }
      linkState = .down
      return .down
    }
  }

  // MARK: - tools/call with transparent permission retry

  func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
    try await ensureReady()

    let backoffs: [UInt64] = [1, 2, 4, 8, 8, 8, 8]
    let budget: TimeInterval = 45
    let start = Date()
    var attempt = 0

    while true {
      do {
        return try await attemptCallTool(name: name, arguments: arguments)
      } catch XbridgeError.bridgeNotRunning {
        let cause = await bridge.lastTerminationCause
        guard cause == .duringToolCall else {
          throw XbridgeError.xcodeUnavailable
        }
        guard Date().timeIntervalSince(start) < budget else {
          linkState = .down
          throw XbridgeError.awaitingPermission
        }
        linkState = .awaitingGrant
        logger.warning("Bridge died during tool call (permission denied suspected) — attempt \(attempt + 1)")
        let delay = attempt < backoffs.count ? backoffs[attempt] : 8
        attempt += 1
        try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
        try await respawnAndHandshake()
      }
    }
  }

  // MARK: - Internal: relink (human debug only — not exposed to agents)

  func relink() async throws {
    try await respawnAndHandshake()
  }

  // MARK: - Private

  private func ensureReady() async throws {
    switch linkState {
    case .ready, .linking, .awaitingGrant:
      return
    case .down:
      try await respawnAndHandshake()
    }
  }

  private func respawnAndHandshake() async throws {
    guard !isRespawning else { return }
    isRespawning = true
    defer { isRespawning = false }

    if await bridge.isRunning {
      await bridge.stop()
    }
    linkState = .linking
    do {
      try await bridge.start()
      try await runHandshake()
      consecutiveHandshakeFailures = 0
      linkState = .ready
    } catch {
      consecutiveHandshakeFailures += 1
      linkState = .down
      if consecutiveHandshakeFailures >= 3 {
        logger.warning("Bridge handshake failed \(consecutiveHandshakeFailures) times — Xcode may be unavailable")
        throw XbridgeError.xcodeUnavailable
      }
      throw error
    }
  }

  private func runHandshake() async throws {
    try await doInitialize()
    knownTools = try await listTools()
    logger.info("MCP ready — \(knownTools.count) tools discovered")
  }

  private func attemptCallTool(name: String, arguments: JSONValue) async throws -> JSONValue {
    guard await bridge.isRunning else { throw XbridgeError.bridgeNotRunning }
    let id = await bridge.nextID()
    let params: JSONValue = [
      "name": .string(name),
      "arguments": arguments
    ]
    let request = MCPRequest(id: id, method: "tools/call", params: params)
    let response = try await bridge.send(request)

    if let err = response.error {
      throw XbridgeError.mcpError(code: err.code, message: err.message)
    }
    guard let result = response.result else {
      throw XbridgeError.invalidResponse("tools/call returned no result")
    }
    let resultData = try JSONEncoder().encode(result)
    if let callResult = try? JSONDecoder().decode(MCPToolCallResult.self, from: resultData),
      callResult.isError == true
    {
      let msg = callResult.content.compactMap(\.text).joined(separator: "\n")
      throw XbridgeError.mcpError(code: -1, message: msg.isEmpty ? "Tool call failed" : msg)
    }
    return result
  }

  // MARK: - MCP initialization

  private func doInitialize() async throws {
    let params = MCPInitializeParams()
    let paramsData = try JSONEncoder().encode(params)
    let paramsJSON = try JSONDecoder().decode(JSONValue.self, from: paramsData)

    let id = await bridge.nextID()
    let request = MCPRequest(id: id, method: "initialize", params: paramsJSON)
    let response = try await bridge.send(request)

    if let err = response.error {
      throw XbridgeError.mcpError(code: err.code, message: err.message)
    }

    let notif = MCPNotification(method: "notifications/initialized")
    let notifData = try JSONEncoder().encode(notif)
    if let line = String(data: notifData, encoding: .utf8) {
      try await bridge.sendRaw(line)
    }

    logger.info("MCP session initialized")
  }

  // MARK: - tools/list

  private func listTools() async throws -> [MCPTool] {
    let id = await bridge.nextID()
    let request = MCPRequest(id: id, method: "tools/list", params: [:])
    let response = try await bridge.send(request)

    if let err = response.error {
      throw XbridgeError.mcpError(code: err.code, message: err.message)
    }
    guard let result = response.result else {
      throw XbridgeError.invalidResponse("tools/list returned no result")
    }
    let resultData = try JSONEncoder().encode(result)
    let toolsList = try JSONDecoder().decode(MCPToolsListResult.self, from: resultData)
    return toolsList.tools
  }
}
