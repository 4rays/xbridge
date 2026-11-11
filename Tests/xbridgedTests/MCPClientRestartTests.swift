import Darwin
import Foundation
import Testing
import XbridgeCore

@testable import xbridged

/// A minimal MCP server in POSIX sh. It answers initialize, tools/list, and tools/call.
/// If the marker file exists at start, it reads one request and exits with no response,
/// like a bridge that cannot reach Xcode.
private let fakeBridgeScript = #"""
  #!/bin/sh
  marker="$1"
  if [ -e "$marker" ]; then
    IFS= read -r line
    exit 0
  fi
  while IFS= read -r line; do
    id=$(printf '%s' "$line" | sed -nE 's/.*"id":([0-9]+).*/\1/p')
    [ -z "$id" ] && continue
    case "$line" in
      *'"method":"initialize"'*)
        printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"fake","version":"1"}}}\n' "$id" ;;
      *list*)
        printf '{"jsonrpc":"2.0","id":%s,"result":{"tools":[{"name":"XcodeListWorkspaces"}]}}\n' "$id" ;;
      *call*)
        printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"ok"}]}}\n' "$id" ;;
    esac
  done
  """#

private struct FakeBridge {
  let directory: URL
  let script: URL
  let marker: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("xbridged-tests-\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    script = directory.appendingPathComponent("fake-mcpbridge.sh")
    marker = directory.appendingPathComponent("unreachable")
    try fakeBridgeScript.write(to: script, atomically: true, encoding: .utf8)
  }

  func makeClient() -> (BridgeProcess, MCPClient) {
    let logger = Logger(
      label: "xbridged-tests",
      fileHandle: FileHandle(forWritingAtPath: "/dev/null") ?? .standardError,
      minimumLevel: .error
    )

    let bridge = BridgeProcess(
      logger: logger,
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: [script.path, marker.path]
    )

    return (bridge, MCPClient(bridge: bridge, logger: logger))
  }

  func makeUnreachable() {
    FileManager.default.createFile(atPath: marker.path, contents: Data())
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private func killIdleBridge(_ bridge: BridgeProcess) async throws {
  let pid = try #require(await bridge.processID)
  Darwin.kill(pid, SIGKILL)
  await bridge.waitUntilTerminated()
  #expect(await bridge.lastTerminationCause == .idle)
}

@Suite("MCP client bridge restart", .serialized)
struct MCPClientRestartTests {
  @Test("Restarts the bridge after an idle exit and retries the tool call")
  func restartsAfterIdleExit() async throws {
    let fake = try FakeBridge()
    defer { fake.remove() }

    let (bridge, client) = fake.makeClient()
    await client.start()
    #expect(await client.linkState == .ready)
    _ = try await client.callTool(name: XcodeTool.listWorkspaces, arguments: [:])

    try await killIdleBridge(bridge)
    #expect(await client.linkState == .ready)

    let result = try await client.callTool(name: XcodeTool.listWorkspaces, arguments: [:])

    #expect(result["content"]?[0]?["text"] == .string("ok"))
    #expect(await bridge.isRunning)
    #expect(await client.linkState == .ready)
    await client.stop()
  }

  @Test("Reports Xcode unavailable when the restart fails")
  func reportsUnavailableWhenRestartFails() async throws {
    let fake = try FakeBridge()
    defer { fake.remove() }

    let (bridge, client) = fake.makeClient()
    await client.start()
    try await killIdleBridge(bridge)
    fake.makeUnreachable()

    let error = await #expect(throws: XbridgeError.self) {
      _ = try await client.callTool(name: XcodeTool.listWorkspaces, arguments: [:])
    }

    guard case .xcodeUnavailable = error else {
      Issue.record("Expected xcodeUnavailable, got \(String(describing: error))")
      return
    }

    await client.stop()
  }
}
