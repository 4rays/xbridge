import Testing
import XbridgeCore

@testable import xbridge

@Suite("Run command")
struct RunCommandTests {
  @Test("Switches destination before launching with workspace and debugger")
  func switchesBeforeRun() throws {
    let extracted = GlobalCLIOptions.extract(
      from: ["--workspace", "workspace1", "run", "--device", "iPhone 18 Pro", "--debugger"]
    )

    let args = Array(extracted.remaining.dropFirst()) + (extracted.debugger ? ["--debugger"] : [])

    var requests: [LocalRPCRequest] = []

    let response = try runProject(args, workspace: extracted.workspace) { request in
      requests.append(request)
      return .success(id: request.id, result: .string("launched"))
    }

    #expect(
      requests.map { $0.params?["tool"]?.stringValue } == [
        XcodeTool.switchRunDestination, XcodeTool.runProject
      ])

    #expect(
      requests.map { $0.params?["arguments"]?["workspaceIdentifier"]?.stringValue } == [
        "workspace1", "workspace1"
      ])

    #expect(requests.first?.params?["arguments"]?["displayTitle"] == .string("iPhone 18 Pro"))
    #expect(requests.last?.params?["arguments"]?["attachDebugger"] == .bool(true))
    #expect(response.ok)
    #expect(response.result == .string("launched"))
  }

  @Test("Does not launch when destination switching fails")
  func failedSwitchPreventsRun() throws {
    var requests: [LocalRPCRequest] = []

    let response = try runProject(["--device", "iPhone 18 Pro"], workspace: "workspace1") {
      request in
      requests.append(request)
      return .failure(id: request.id, message: "Destination unavailable")
    }

    #expect(requests.map { $0.params?["tool"]?.stringValue } == [XcodeTool.switchRunDestination])
    #expect(!response.ok)
    #expect(response.error?.message == "Destination unavailable")
  }

  @Test("Launches the selected destination without attaching a debugger by default")
  func runsWithoutSwitching() throws {
    var requests: [LocalRPCRequest] = []

    _ = try runProject([], workspace: nil) { request in
      requests.append(request)
      return .success(id: request.id, result: .null)
    }

    #expect(requests.map { $0.params?["tool"]?.stringValue } == [XcodeTool.runProject])
    #expect(requests.first?.params?["arguments"] == .object([:]))
  }
}
