import Foundation
import XbridgeCore

// MARK: - Command

struct Command: Sendable {
  let name: String
  let usage: String
  let minArgs: Int
  let build: @Sendable ([String]) throws -> LocalRPCRequest
}

// MARK: - Registry

enum Commands {
  static let all: [Command] = [
    statusCommand,
    stopCommand,
    relinkCommand,
    toolsCommand,
    toolSchemaCommand,
    callCommand,
    listWorkspacesCommand,
    listWindowsCommand,
    openWorkspaceCommand,
    closeWorkspaceCommand,
    listSchemesCommand,
    switchSchemeCommand,
    listDestinationsCommand,
    switchDestinationCommand,
    listTargetsCommand,
    listTestPlansCommand,
    switchTestPlanCommand,
    buildCommand,
    runCommand,
    stopRunCommand,
    testCommand,
    testListCommand,
    runTestsCommand,
    readCommand,
    grepCommand,
    issuesCommand,
    refreshIssuesCommand,
    buildLogCommand,
    consoleCommand,
    debugCommand,
    lsCommand,
    globCommand,
    mkdirCommand,
    rmCommand,
    mvCommand,
    writeCommand,
    updateCommand,
    execCommand,
    previewCommand,
    buildSettingsCommand,
    docsCommand,
    deviceStartCommand,
    deviceSessionCommand,
    deviceEndCommand,
    deviceInstallCommand,
    deviceInteractCommand
  ]

  static func find(named name: String) -> Command? {
    all.first { $0.name == name }
  }

  static let hidden: Set<String> = ["relink", "list-windows"]

  static func printHelp() {
    print("Usage: xbridge [--workspace <id>] <command> [args]")
    print("")
    print("  --workspace <id>           Target a workspace when several are open")
    print("")
    print("Commands:")
    print("  version                    Show version")
    for cmd in all where !hidden.contains(cmd.name) {
      print("  \(cmd.usage)")
    }
  }

  // MARK: - Lifecycle commands

  static let statusCommand = Command(
    name: "status",
    usage: "status                    Show daemon and bridge status",
    minArgs: 0
  ) { _ in
    LocalRPCRequest(method: LocalRPCMethod.status)
  }

  static let stopCommand = Command(
    name: "stop",
    usage: "stop [--force]            Stop the daemon (requires interactive terminal)",
    minArgs: 0
  ) { _ in
    LocalRPCRequest(method: LocalRPCMethod.stop)
  }

  static let relinkCommand = Command(
    name: "relink",
    usage: "relink                    Re-run MCP handshake without restarting the bridge",
    minArgs: 0
  ) { _ in
    LocalRPCRequest(method: LocalRPCMethod.relink)
  }

  static let toolsCommand = Command(
    name: "tools",
    usage: "tools                     List MCP tools discovered from Xcode",
    minArgs: 0
  ) { _ in
    LocalRPCRequest(method: LocalRPCMethod.tools)
  }

  static let toolSchemaCommand = Command(
    name: "tool-schema",
    usage: "tool-schema <ToolName>    Show input schema for an MCP tool",
    minArgs: 1
  ) { args in
    LocalRPCRequest(method: LocalRPCMethod.toolSchema, params: ["name": .string(args[0])])
  }

  // MARK: - Generic call

  static let callCommand = Command(
    name: "call",
    usage: "call <ToolName> [json]      Call any MCP tool with optional JSON arguments",
    minArgs: 1
  ) { args in
    let tool = args[0]
    var arguments: JSONValue = [:]
    if args.count >= 2 {
      let raw = args[1]
      guard
        let data = raw.data(using: .utf8),
        let parsed = try? JSONDecoder().decode(JSONValue.self, from: data)
      else {
        throw XbridgeError.decodingError("Arguments must be valid JSON, e.g. '{\"key\":\"value\"}'")
      }
      arguments = parsed
    }
    return callToolRequest(tool: tool, arguments: arguments)
  }

  // MARK: - Workspace / scheme / destination

  static let listWorkspacesCommand = Command(
    name: "list-workspaces",
    usage: "list-workspaces           List open Xcode workspaces",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.listWorkspaces, arguments: [:])
  }

  /// Hidden alias for list-workspaces (pre-Xcode 27 command name).
  static let listWindowsCommand = Command(
    name: "list-windows",
    usage: "list-windows              Alias for list-workspaces",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.listWorkspaces, arguments: [:])
  }

  static let openWorkspaceCommand = Command(
    name: "open-workspace",
    usage: "open-workspace <path>     Open a .xcworkspace or .xcodeproj",
    minArgs: 1
  ) { args in
    callToolRequest(tool: XcodeTool.openWorkspace, arguments: ["path": .string(args[0])])
  }

  static let closeWorkspaceCommand = Command(
    name: "close-workspace",
    usage: "close-workspace <id>      Close a workspace by identifier",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.closeWorkspace,
      arguments: ["workspaceIdentifier": .string(args[0])]
    )
  }

  static let listSchemesCommand = Command(
    name: "list-schemes",
    usage: "list-schemes              List schemes in the current workspace",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.listSchemes, arguments: [:])
  }

  static let switchSchemeCommand = Command(
    name: "switch-scheme",
    usage: "switch-scheme <name>      Make a scheme active",
    minArgs: 1
  ) { args in
    callToolRequest(tool: XcodeTool.switchScheme, arguments: ["schemeName": .string(args[0])])
  }

  static let listDestinationsCommand = Command(
    name: "list-destinations",
    usage: "list-destinations         List run destinations for the active scheme",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.listRunDestinations, arguments: [:])
  }

  static let switchDestinationCommand = Command(
    name: "switch-destination",
    usage: "switch-destination <title>  Make a run destination active",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.switchRunDestination,
      arguments: ["displayTitle": .string(args[0])]
    )
  }

  static let listTargetsCommand = Command(
    name: "list-targets",
    usage: "list-targets              List targets in the current workspace",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.listTargets, arguments: [:])
  }

  static let listTestPlansCommand = Command(
    name: "list-test-plans",
    usage: "list-test-plans           List test plans for the active scheme",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.listTestPlans, arguments: [:])
  }

  static let switchTestPlanCommand = Command(
    name: "switch-test-plan",
    usage: "switch-test-plan <name>   Make a test plan active",
    minArgs: 1
  ) { args in
    callToolRequest(tool: XcodeTool.switchTestPlan, arguments: ["testPlanName": .string(args[0])])
  }

  // MARK: - Build / run / test

  static let buildCommand = Command(
    name: "build",
    usage: "build                     Build the current scheme",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.buildProject, arguments: [:])
  }

  static let runCommand = Command(
    name: "run",
    usage: "run                       Build and run the current scheme",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.runProject, arguments: [:])
  }

  static let stopRunCommand = Command(
    name: "stop-run",
    usage: "stop-run                  Stop the running app",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.stopProject, arguments: [:])
  }

  static let testCommand = Command(
    name: "test",
    usage: "test                      Run all tests in the active test plan",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.runAllTests, arguments: [:])
  }

  static let testListCommand = Command(
    name: "test-list",
    usage: "test-list                 List available tests in the active test plan",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.listTests, arguments: [:])
  }

  static let runTestsCommand = Command(
    name: "test-run",
    usage: "test-run <target> <identifier>  Run a specific test",
    minArgs: 2
  ) { args in
    let tests: JSONValue = .array([
      .object(["targetName": .string(args[0]), "testIdentifier": .string(args[1])])
    ])
    return callToolRequest(tool: XcodeTool.runSomeTests, arguments: ["tests": tests])
  }

  static let issuesCommand = Command(
    name: "issues",
    usage: "issues [severity]         Show build issues (severity: error|warning|remark, default: error)",
    minArgs: 0
  ) { args in
    var dict: [String: JSONValue] = [:]
    if args.count > 0 {
      dict["severity"] = .string(args[0])
    }
    return callToolRequest(tool: XcodeTool.getBuildLog, arguments: .object(dict))
  }

  static let buildLogCommand = Command(
    name: "build-log",
    usage: "build-log                 Show the current or latest build log",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.getBuildLog, arguments: [:])
  }

  static let consoleCommand = Command(
    name: "console",
    usage: "console                   Show console output from the latest launch",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.getConsoleOutput, arguments: [:])
  }

  static let debugCommand = Command(
    name: "debug",
    usage: "debug <command>           Send an lldb command to the active debug session",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.invokeDebuggerCommand,
      arguments: ["command": .string(args[0])]
    )
  }

  static let buildSettingsCommand = Command(
    name: "build-settings",
    usage: "build-settings <target>   Show build settings for a target",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.getTargetBuildSettings,
      arguments: ["targetName": .string(args[0])]
    )
  }

  // MARK: - File operations

  static let readCommand = Command(
    name: "read",
    usage: "read <file>               Read a file in the current workspace",
    minArgs: 1
  ) { args in
    callToolRequest(tool: XcodeTool.readFile, arguments: ["filePath": .string(args[0])])
  }

  static let grepCommand = Command(
    name: "grep",
    usage: "grep <pattern> [path]     Search in the current workspace",
    minArgs: 1
  ) { args in
    var toolArgs: JSONValue = ["pattern": .string(args[0])]
    if args.count >= 2, var obj = toolArgs.objectValue {
      obj["path"] = .string(args[1])
      toolArgs = .object(obj)
    }
    return callToolRequest(tool: XcodeTool.grepInProject, arguments: toolArgs)
  }

  static let lsCommand = Command(
    name: "ls",
    usage: "ls <path>                 List files in the Xcode project at path",
    minArgs: 1
  ) { args in
    callToolRequest(tool: XcodeTool.listFiles, arguments: ["path": .string(args[0])])
  }

  static let globCommand = Command(
    name: "glob",
    usage: "glob [pattern]            Find files matching a wildcard pattern",
    minArgs: 0
  ) { args in
    var toolArgs: JSONValue = [:]
    if args.count >= 1, var obj = toolArgs.objectValue {
      obj["pattern"] = .string(args[0])
      toolArgs = .object(obj)
    }
    return callToolRequest(tool: XcodeTool.globFiles, arguments: toolArgs)
  }

  static let mkdirCommand = Command(
    name: "mkdir",
    usage: "mkdir <path>              Create a directory in the Xcode project",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.makeDir,
      arguments: ["directoryPath": .string(args[0])]
    )
  }

  static let rmCommand = Command(
    name: "rm",
    usage: "rm <path>                 Remove a file or directory from the Xcode project",
    minArgs: 1
  ) { args in
    callToolRequest(tool: XcodeTool.removeFile, arguments: ["path": .string(args[0])])
  }

  static let mvCommand = Command(
    name: "mv",
    usage: "mv <src> <dst>            Move or rename a file in the Xcode project",
    minArgs: 2
  ) { args in
    callToolRequest(
      tool: XcodeTool.moveFile,
      arguments: [
        "sourcePath": .string(args[0]),
        "destinationPath": .string(args[1])
      ]
    )
  }

  static let writeCommand = Command(
    name: "write",
    usage: "write <path> <content>    Create or overwrite a file",
    minArgs: 2
  ) { args in
    callToolRequest(
      tool: XcodeTool.writeFile,
      arguments: [
        "filePath": .string(args[0]),
        "content": .string(args[1])
      ]
    )
  }

  static let updateCommand = Command(
    name: "update",
    usage: "update <path> <old> <new> Replace text in a file",
    minArgs: 3
  ) { args in
    callToolRequest(
      tool: XcodeTool.updateFile,
      arguments: [
        "filePath": .string(args[0]),
        "oldString": .string(args[1]),
        "newString": .string(args[2])
      ]
    )
  }

  static let refreshIssuesCommand = Command(
    name: "refresh-issues",
    usage: "refresh-issues <file>     Refresh compiler diagnostics for a file",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.refreshIssues,
      arguments: ["filePath": .string(args[0])]
    )
  }

  static let execCommand = Command(
    name: "exec",
    usage: "exec <file> <purpose> <code>  Execute a Swift code snippet",
    minArgs: 3
  ) { args in
    callToolRequest(
      tool: XcodeTool.runCodeSnippet,
      arguments: [
        "sourceFilePath": .string(args[0]),
        "purpose": .string(args[1]),
        "codeSnippet": .string(args[2])
      ]
    )
  }

  static let previewCommand = Command(
    name: "preview",
    usage: "preview <file> [index]    Render a SwiftUI preview",
    minArgs: 1
  ) { args in
    var toolArgs: JSONValue = ["sourceFilePath": .string(args[0])]
    if args.count >= 2, let idx = Int(args[1]), var obj = toolArgs.objectValue {
      obj["previewDefinitionIndexInFile"] = .int(idx)
      toolArgs = .object(obj)
    }
    return callToolRequest(tool: XcodeTool.renderPreview, arguments: toolArgs)
  }

  static let docsCommand = Command(
    name: "docs",
    usage: "docs <query> [framework]  Search Apple Developer Documentation",
    minArgs: 1
  ) { args in
    var toolArgs: JSONValue = ["query": .string(args[0])]
    if args.count >= 2, var obj = toolArgs.objectValue {
      obj["frameworks"] = .array([.string(args[1])])
      toolArgs = .object(obj)
    }
    return callToolRequest(tool: XcodeTool.documentationSearch, arguments: toolArgs)
  }

  // MARK: - Device interaction

  static let deviceStartCommand = Command(
    name: "device-start",
    usage: "device-start <session> [device]  Start a workspace-bound device session",
    minArgs: 1
  ) { args in
    var dict: [String: JSONValue] = ["sessionIdentifier": .string(args[0])]
    if args.count >= 2 {
      dict["deviceIdentifier"] = .string(args[1])
    }
    return callToolRequest(
      tool: XcodeTool.deviceInteractionStartWorkspaceSession,
      arguments: .object(dict)
    )
  }

  static let deviceSessionCommand = Command(
    name: "device-session",
    usage: "device-session <device> <session>  Start a device session without a workspace",
    minArgs: 2
  ) { args in
    callToolRequest(
      tool: XcodeTool.deviceInteractionStartSession,
      arguments: [
        "deviceIdentifier": .string(args[0]),
        "sessionIdentifier": .string(args[1])
      ]
    )
  }

  static let deviceEndCommand = Command(
    name: "device-end",
    usage: "device-end <key>          End a device session",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.deviceInteractionEndSession,
      arguments: ["interactionSessionKey": .string(args[0])]
    )
  }

  static let deviceInstallCommand = Command(
    name: "device-install",
    usage: "device-install <key>      Build, install, and run on the session device",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.deviceInteractionInstallAndRun,
      arguments: ["interactionSessionKey": .string(args[0])]
    )
  }

  static let deviceInteractCommand = Command(
    name: "device-interact",
    usage: "device-interact <key> [command] [bundle-id]  Synthesize a device event",
    minArgs: 1
  ) { args in
    var dict: [String: JSONValue] = ["interactSessionKey": .string(args[0])]
    if args.count >= 2 {
      dict["interactionCommand"] = .string(args[1])
    }
    if args.count >= 3 {
      dict["activationBundleId"] = .string(args[2])
    }
    return callToolRequest(
      tool: XcodeTool.deviceInteractionSynthesize,
      arguments: .object(dict)
    )
  }

  // MARK: - Helper

  private static func callToolRequest(tool: String, arguments: JSONValue) -> LocalRPCRequest {
    let params = CallToolParams(tool: tool, arguments: arguments)
    let paramsData = (try? JSONEncoder().encode(params)) ?? Data()
    let paramsJSON = (try? JSONDecoder().decode(JSONValue.self, from: paramsData)) ?? .null
    return LocalRPCRequest(method: LocalRPCMethod.callTool, params: paramsJSON)
  }
}
