import Foundation
import Testing
@testable import XbridgeCore

@Suite("LocalRPC encoding and decoding")
struct LocalRPCTests {
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  // MARK: - LocalRPCRequest

  @Test("Request encodes to expected JSON keys")
  func requestEncoding() throws {
    let req = LocalRPCRequest(id: "abc", method: "status")
    let data = try encoder.encode(req)
    let json = try decoder.decode([String: JSONValue].self, from: data)

    #expect(json["id"] == .string("abc"))
    #expect(json["method"] == .string("status"))
    #expect(json["params"]?.isNull ?? true)
  }

  @Test("Request with params round-trips correctly")
  func requestWithParamsRoundTrip() throws {
    let params: JSONValue = ["tool": "list_windows_and_tabs", "arguments": [:]]
    let req = LocalRPCRequest(id: "1", method: "callTool", params: params)
    let data = try encoder.encode(req)
    let decoded = try decoder.decode(LocalRPCRequest.self, from: data)

    #expect(decoded.id == "1")
    #expect(decoded.method == "callTool")
    #expect(decoded.params?["tool"]?.stringValue == "list_windows_and_tabs")
  }

  // MARK: - LocalRPCResponse

  @Test("Success factory sets ok=true and populates result")
  func successResponse() throws {
    let result: JSONValue = ["daemon": "running", "bridge": "healthy"]
    let resp = LocalRPCResponse.success(id: "42", result: result)

    #expect(resp.id == "42")
    #expect(resp.ok == true)
    #expect(resp.error == nil)
    #expect(resp.result?["daemon"]?.stringValue == "running")
  }

  @Test("Failure factory sets ok=false and populates error")
  func failureResponse() throws {
    let resp = LocalRPCResponse.failure(id: "7", message: "Bridge not running")

    #expect(resp.id == "7")
    #expect(resp.ok == false)
    #expect(resp.result == nil)
    #expect(resp.error?.message == "Bridge not running")
  }

  @Test("Response round-trips through JSON")
  func responseRoundTrip() throws {
    let original = LocalRPCResponse.success(id: "r1", result: .string("ok"))
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(LocalRPCResponse.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.ok == original.ok)
    #expect(decoded.result?.stringValue == "ok")
  }

  // MARK: - CallToolParams

  @Test("CallToolParams encodes and decodes correctly")
  func callToolParamsRoundTrip() throws {
    let params = CallToolParams(
      tool: "build_project",
      arguments: ["tabIdentifier": "win1"]
    )
    let data = try encoder.encode(params)
    let decoded = try decoder.decode(CallToolParams.self, from: data)

    #expect(decoded.tool == "build_project")
    #expect(decoded.arguments["tabIdentifier"]?.stringValue == "win1")
  }

  @Test("injectingWorkspace adds workspaceIdentifier when missing")
  func injectingWorkspaceAddsIdentifier() {
    let params = CallToolParams(tool: XcodeTool.buildProject, arguments: [:])
    let injected = params.injectingWorkspace("workspace1")
    #expect(injected.arguments["workspaceIdentifier"]?.stringValue == "workspace1")
  }

  @Test("injectingWorkspace does not overwrite an existing identifier")
  func injectingWorkspacePreservesExisting() {
    let params = CallToolParams(
      tool: XcodeTool.buildProject,
      arguments: ["workspaceIdentifier": "existing"]
    )
    let injected = params.injectingWorkspace("workspace1")
    #expect(injected.arguments["workspaceIdentifier"]?.stringValue == "existing")
  }

  @Test("injectingWorkspace skips tools that reject workspaceIdentifier")
  func injectingWorkspaceSkipsListWorkspaces() {
    let params = CallToolParams(tool: XcodeTool.listWorkspaces, arguments: [:])
    let injected = params.injectingWorkspace("workspace1")
    #expect(injected.arguments["workspaceIdentifier"] == nil)
  }
}
