import Darwin
import Foundation
import XbridgeCore

let extracted = GlobalCLIOptions.extract(from: Array(CommandLine.arguments.dropFirst()))
let xcodePath = extracted.xcodePath
let workspace = extracted.workspace
let args = extracted.remaining

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
  print("xbridge 0.9.1")
  exit(0)
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
  var request = try command.build(commandArgs)
  if let workspace, request.method == LocalRPCMethod.callTool,
    let paramsData = try? JSONEncoder().encode(request.params),
    let params = try? JSONDecoder().decode(CallToolParams.self, from: paramsData)
  {
    let injected = params.injectingWorkspace(workspace)
    let injectedData = (try? JSONEncoder().encode(injected)) ?? Data()
    let injectedJSON = (try? JSONDecoder().decode(JSONValue.self, from: injectedData)) ?? .null
    request = LocalRPCRequest(id: request.id, method: request.method, params: injectedJSON)
  }
  let client = DaemonClient(xcodePath: xcodePath)

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
