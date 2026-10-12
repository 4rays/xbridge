import Darwin
import Foundation
import XbridgeCore

let extracted = GlobalCLIOptions.extract(from: Array(CommandLine.arguments.dropFirst()))
let xcodePath = extracted.xcodePath
let workspace = extracted.workspace
let args = extracted.remaining + (extracted.debugger ? ["--debugger"] : [])

guard !args.isEmpty else {
  Commands.printHelp()
  exit(0)
}

let commandName = args[0]
let commandArgs = Array(args.dropFirst())

// Handle --help / -h
if commandName == "--help" || commandName == "-h" || commandName == "help" {
  Commands.printHelp()
  exit(0)
}

// Handle version
if commandName == "--version" || commandName == "-v" || commandName == "version" {
  print("xbridge 0.9.4")
  exit(0)
}

if commandName == "skill" {
  guard commandArgs.isEmpty else {
    fputs("usage: xbridge skill\n", stderr)
    exit(1)
  }
  do {
    try FileHandle.standardOutput.write(contentsOf: SkillDocument.contents())
    exit(0)
  } catch {
    fputs("error: cannot read bundled skill: \(error.localizedDescription)\n", stderr)
    exit(1)
  }
}

if commandName == "status", !commandArgs.isEmpty {
  do {
    guard workspace == nil else { throw StatusRepairError.workspaceID }
    let projectPath = try StatusRepair.projectPath(from: commandArgs)
    print(try StatusRepair.allow(projectPath: projectPath))
    let response = try DaemonClient(xcodePath: xcodePath).send(
      LocalRPCRequest(method: LocalRPCMethod.status)
    )
    print(OutputFormatter.format(response: response, method: LocalRPCMethod.status))
    exit(response.ok ? 0 : 1)
  } catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
  }
}

guard let command = Commands.find(named: commandName) else {
  fputs("error: unknown command '\(commandName)'\n\n", stderr)
  Commands.printHelp()
  exit(1)
}

guard commandArgs.count >= command.minArgs else {
  fputs("error: '\(commandName)' requires at least \(command.minArgs) argument(s)\n", stderr)
  fputs("usage: xbridge \(command.usage)\n", stderr)
  exit(1)
}

do {
  let client = DaemonClient(xcodePath: xcodePath)
  let runArgs = try commandName == "run" ? prepareRun(commandArgs, workspace: workspace, client: client) : commandArgs

  var request = try command.build(runArgs)
  if let workspace {
    request = injectWorkspace(workspace, into: request)
  }
  if request.method == LocalRPCMethod.stop {
    guard Darwin.isatty(STDIN_FILENO) == 1 || commandArgs.contains("--force") else {
      fputs("error: 'stop' requires an interactive terminal; use --force to override\n", stderr)
      exit(1)
    }
    if let response = try? client.send(request, autoStart: false) {
      let output = OutputFormatter.format(response: response, method: request.method)
      print(output)
      exit(response.ok ? 0 : 1)
    }

    let cleanup = DaemonProcessCleanup.cleanupExistingDaemons()
    print(cleanup.didCleanup ? "stopped" : "xbridged is not running")
    exit(0)
  }

  let response = try client.send(request)

  let output = OutputFormatter.format(response: response, method: request.method)
  print(output)

  exit(response.ok ? 0 : 1)
} catch {
  fputs("error: \(error.localizedDescription)\n", stderr)
  exit(1)
}

private func prepareRun(
  _ args: [String],
  workspace: String?,
  client: DaemonClient
) throws -> [String] {
  guard let device = try runDevice(from: args) else { return args }
  var request = try Commands.switchDestinationCommand.build([device])
  if let workspace {
    request = injectWorkspace(workspace, into: request)
  }
  let switched = try client.send(request)
  guard switched.ok else {
    print(OutputFormatter.format(response: switched, method: LocalRPCMethod.callTool))
    exit(1)
  }
  return args.filter { $0 != "--device" && $0 != device }
}

private func injectWorkspace(_ workspace: String, into request: LocalRPCRequest) -> LocalRPCRequest {
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
