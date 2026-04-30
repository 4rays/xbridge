import Foundation
import XbridgeCore

/// The main coordinator for xhammerd.
///
/// Owns the MCP client, the socket server, and the state store.
/// Handles incoming LocalRPC requests from CLI connections.
actor DaemonServer {
  private let mcpClient: MCPClient
  private let stateStore: StateStore
  private let logger: Logger
  private var socketServer: SocketServer?

  init(logger: Logger) {
    self.logger = logger
    let bridge = BridgeProcess(logger: logger)
    self.mcpClient = MCPClient(bridge: bridge, logger: logger)
    self.stateStore = StateStore(logger: logger)
  }

  // MARK: - Run

  func run() async throws {
    try XbridgePaths.ensureDirectoryExists()
    _ = DaemonProcessCleanup.cleanupExistingDaemons(
      excluding: Int32(ProcessInfo.processInfo.processIdentifier)
    ) { [logger] message in
      logger.warning(message)
    }

    await stateStore.writePID(Int32(ProcessInfo.processInfo.processIdentifier))

    logger.info("Starting MCP client...")
    try await mcpClient.start()

    let server = SocketServer(logger: logger) { [weak self] fd in
      guard let self else { return }
      await self.handleConnection(fd: fd)
    }
    socketServer = server
    try await server.start(socketPath: XbridgePaths.socketPath.path)

    logger.info("xbridged ready")

    // Block until the process receives a signal (SIGTERM/SIGINT handled in main.swift).
    try await Task.sleep(nanoseconds: .max)
  }

  func shutdown() async {
    logger.info("Shutting down...")
    if let server = socketServer {
      await server.stop()
    }
    await mcpClient.stop()
    await stateStore.removePID()
    await stateStore.removeSocket()
  }

  // MARK: - Connection handler

  func handleConnection(fd: Int32) async {
    guard let line = readLine(fd: fd), !line.isEmpty else { return }

    guard
      let data = line.data(using: .utf8),
      let request = try? JSONDecoder().decode(LocalRPCRequest.self, from: data)
    else {
      let resp = LocalRPCResponse.failure(id: "?", message: "Invalid request format")
      sendResponse(resp, fd: fd)
      return
    }

    let response = await processRequest(request)
    sendResponse(response, fd: fd)
  }

  private func sendResponse(_ response: LocalRPCResponse, fd: Int32) {
    guard
      let data = try? JSONEncoder().encode(response),
      let line = String(data: data, encoding: .utf8)
    else { return }
    writeLine(line, fd: fd)
  }

  // MARK: - Request dispatch

  private func processRequest(_ request: LocalRPCRequest) async -> LocalRPCResponse {
    switch request.method {
    case LocalRPCMethod.status:
      return await handleStatus(id: request.id)
    case LocalRPCMethod.stop:
      return await handleStop(id: request.id)
    case LocalRPCMethod.restart:
      return await handleRestart(id: request.id)
    case LocalRPCMethod.tools:
      return await handleTools(id: request.id)
    case LocalRPCMethod.toolSchema:
      return await handleToolSchema(request)
    case LocalRPCMethod.callTool:
      return await handleCallTool(request)
    default:
      return .failure(id: request.id, message: "Unknown method: \(request.method)")
    }
  }

  // MARK: - Handlers

  private func handleStatus(id: String) async -> LocalRPCResponse {
    let bridgeOK = await mcpClient.isInitialized
    let toolCount = await mcpClient.knownTools.count
    let result: JSONValue = [
      "daemon": "running",
      "bridge": .string(bridgeOK ? "healthy" : "not ready"),
      "tools": .int(toolCount)
    ]
    return .success(id: id, result: result)
  }

  private func handleStop(id: String) async -> LocalRPCResponse {
    Task {
      try? await Task.sleep(nanoseconds: 100_000_000)
      await self.shutdown()
      exit(0)
    }
    return .success(id: id, result: ["message": "stopping"])
  }

  private func handleRestart(id: String) async -> LocalRPCResponse {
    do {
      try await mcpClient.restart()
      return .success(id: id, result: ["message": "restarted"])
    } catch {
      return .failure(id: id, message: error.localizedDescription)
    }
  }

  private func handleTools(id: String) async -> LocalRPCResponse {
    let tools = await mcpClient.knownTools
    let names = tools.map { JSONValue.string($0.name) }
    return .success(id: id, result: .array(names))
  }

  private func handleToolSchema(_ request: LocalRPCRequest) async -> LocalRPCResponse {
    guard let name = request.params?["name"]?.stringValue else {
      return .failure(id: request.id, message: "toolSchema requires {name}")
    }
    let tools = await mcpClient.knownTools
    guard let tool = tools.first(where: { $0.name == name }) else {
      return .failure(id: request.id, message: "Unknown tool: \(name)")
    }
    let result: JSONValue = [
      "name": .string(tool.name),
      "description": .string(tool.description ?? ""),
      "inputSchema": tool.inputSchema ?? .null
    ]
    return .success(id: request.id, result: result)
  }

  private func handleCallTool(_ request: LocalRPCRequest) async -> LocalRPCResponse {
    guard
      let paramsJSON = request.params,
      let paramsData = try? JSONEncoder().encode(paramsJSON),
      let params = try? JSONDecoder().decode(CallToolParams.self, from: paramsData)
    else {
      return .failure(id: request.id, message: "callTool requires {tool, arguments} params")
    }

    do {
      let result = try await mcpClient.callTool(name: params.tool, arguments: params.arguments)
      return .success(id: request.id, result: result)
    } catch {
      return .failure(id: request.id, message: error.localizedDescription)
    }
  }
}
