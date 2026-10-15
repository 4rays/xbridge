import Foundation
import XbridgeCore

func runProject(
  _ args: [String],
  workspace: String?,
  send: (LocalRPCRequest) throws -> LocalRPCResponse
) throws -> LocalRPCResponse {
  var runArgs = args

  if let device = try runDevice(from: args) {
    var request = try Commands.switchDestinationCommand.build([device])

    if let workspace {
      request = injectWorkspace(workspace, into: request)
    }

    let switched = try send(request)
    guard switched.ok else { return switched }
    runArgs = args.filter { $0 != "--device" && $0 != device }
  }

  var request = try Commands.runCommand.build(runArgs)

  if let workspace {
    request = injectWorkspace(workspace, into: request)
  }

  return try send(request)
}

func injectWorkspace(_ workspace: String, into request: LocalRPCRequest) -> LocalRPCRequest {
  guard request.method == LocalRPCMethod.callTool,
    let paramsData = try? JSONEncoder().encode(request.params),
    let params = try? JSONDecoder().decode(CallToolParams.self, from: paramsData)
  else { return request }

  let injected = params.injectingWorkspace(workspace)
  let injectedData = (try? JSONEncoder().encode(injected)) ?? Data()
  let injectedJSON = (try? JSONDecoder().decode(JSONValue.self, from: injectedData)) ?? .null
  return LocalRPCRequest(id: request.id, method: request.method, params: injectedJSON)
}

private func runDevice(from args: [String]) throws -> String? {
  guard let index = args.firstIndex(of: "--device") else { return nil }
  let valueIndex = args.index(after: index)

  guard valueIndex < args.endIndex, !args[valueIndex].hasPrefix("--") else {
    throw RunFlagError.missingDevice
  }

  return args[valueIndex]
}

private enum RunFlagError: LocalizedError {
  case missingDevice

  var errorDescription: String? {
    switch self {
    case .missingDevice:
      return "'run --device' requires a destination title"
    }
  }
}
