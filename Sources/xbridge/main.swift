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
  print("xbridge 0.9.7")
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

if commandName == "status" {
  do {
    let projectPath: String?

    if commandArgs.isEmpty {
      projectPath = nil
    } else {
      guard workspace == nil else { throw StatusRepairError.workspaceID }
      projectPath = try StatusRepair.projectPath(from: commandArgs)
    }

    print("Xcode MCP server (xcrun mcp-server status --format json):")
    print(try StatusRepair.status(xcodePath: xcodePath))

    if let projectPath {
      print("\n" + StatusRepair.instructions(projectPath: projectPath))
      exit(0)
    }

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

  var request = try command.build(commandArgs)

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

  let response =
    try commandName == "run"
    ? runProject(commandArgs, workspace: workspace, send: { try client.send($0) })
    : client.send(request)

  let output = OutputFormatter.format(response: response, method: request.method)
  print(output)

  exit(response.ok ? 0 : 1)
} catch {
  fputs("error: \(error.localizedDescription)\n", stderr)
  exit(1)
}
