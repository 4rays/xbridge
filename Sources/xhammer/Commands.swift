import Foundation
import XhammerCore

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
    restartCommand,
    toolsCommand,
    toolSchemaCommand,
    callCommand,
    listWindowsCommand,
    buildCommand,
    testCommand,
    testListCommand,
    readCommand,
    grepCommand,
    issuesCommand,
    refreshIssuesCommand,
    buildLogCommand,
    lsCommand,
    globCommand,
    runTestsCommand,
    mkdirCommand,
    rmCommand,
    mvCommand,
    writeCommand,
    updateCommand,
    execCommand,
    previewCommand,
    docsCommand
  ]

  static func find(named name: String) -> Command? {
    all.first { $0.name == name }
  }

  static func printHelp() {
    print("Usage: xhammer <command> [args]")
    print("")
    print("Commands:")
    for cmd in all {
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
    usage: "stop                      Stop the daemon",
    minArgs: 0
  ) { _ in
    LocalRPCRequest(method: LocalRPCMethod.stop)
  }

  static let restartCommand = Command(
    name: "restart",
    usage: "restart                   Restart the Xcode MCP bridge",
    minArgs: 0
  ) { _ in
    LocalRPCRequest(method: LocalRPCMethod.restart)
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
        throw XhammerError.decodingError("Arguments must be valid JSON, e.g. '{\"key\":\"value\"}'")
      }
      arguments = parsed
    }
    return callToolRequest(tool: tool, arguments: arguments)
  }

  // MARK: - Xcode tool commands

  static let listWindowsCommand = Command(
    name: "list-windows",
    usage: "list-windows              List open Xcode windows and tabs",
    minArgs: 0
  ) { _ in
    callToolRequest(tool: XcodeTool.listWindows, arguments: [:])
  }

  static let buildCommand = Command(
    name: "build",
    usage: "build <tab-id>            Build the project in the specified tab",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.buildProject,
      arguments: ["tabIdentifier": .string(args[0])]
    )
  }

  static let testCommand = Command(
    name: "test",
    usage: "test <tab-id>             Run tests in the specified tab",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.runAllTests,
      arguments: ["tabIdentifier": .string(args[0])]
    )
  }

  static let testListCommand = Command(
    name: "test-list",
    usage: "test-list <tab-id>        List available tests in the specified tab",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.listTests,
      arguments: ["tabIdentifier": .string(args[0])]
    )
  }

  static let readCommand = Command(
    name: "read",
    usage: "read <file> <tab-id>      Read a file in the specified tab",
    minArgs: 2
  ) { args in
    callToolRequest(
      tool: XcodeTool.readFile,
      arguments: [
        "path": .string(args[0]),
        "tabIdentifier": .string(args[1])
      ]
    )
  }

  static let grepCommand = Command(
    name: "grep",
    usage: "grep <pattern> <tab-id> [path]  Search in the specified tab",
    minArgs: 2
  ) { args in
    var toolArgs: JSONValue = [
      "pattern": .string(args[0]),
      "tabIdentifier": .string(args[1])
    ]
    if args.count >= 3, var obj = toolArgs.objectValue {
      obj["path"] = .string(args[2])
      toolArgs = .object(obj)
    }
    return callToolRequest(tool: XcodeTool.grepInProject, arguments: toolArgs)
  }

  static let issuesCommand = Command(
    name: "issues",
    usage: "issues <tab-id>           Show build issues in the specified tab",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.listIssues,
      arguments: ["tabIdentifier": .string(args[0])]
    )
  }

  static let buildLogCommand = Command(
    name: "build-log",
    usage: "build-log <tab-id>        Show the build log for the specified tab",
    minArgs: 1
  ) { args in
    callToolRequest(
      tool: XcodeTool.getBuildLog,
      arguments: ["tabIdentifier": .string(args[0])]
    )
  }

  static let lsCommand = Command(
    name: "ls",
    usage: "ls <tab-id> <path>        List files in the Xcode project at path",
    minArgs: 2
  ) { args in
    callToolRequest(
      tool: XcodeTool.listFiles,
      arguments: ["tabIdentifier": .string(args[0]), "path": .string(args[1])]
    )
  }

  static let globCommand = Command(
    name: "glob",
    usage: "glob <tab-id> [pattern]   Find files matching a wildcard pattern",
    minArgs: 1
  ) { args in
    var toolArgs: JSONValue = ["tabIdentifier": .string(args[0])]
    if args.count >= 2, var obj = toolArgs.objectValue {
      obj["pattern"] = .string(args[1])
      toolArgs = .object(obj)
    }
    return callToolRequest(tool: XcodeTool.globFiles, arguments: toolArgs)
  }

  static let runTestsCommand = Command(
    name: "test-run",
    usage: "test-run <tab-id> <target> <identifier>  Run a specific test",
    minArgs: 3
  ) { args in
    let tests: JSONValue = .array([
      .object(["targetName": .string(args[1]), "testIdentifier": .string(args[2])])
    ])
    return callToolRequest(
      tool: XcodeTool.runSomeTests,
      arguments: ["tabIdentifier": .string(args[0]), "tests": tests]
    )
  }

  static let mkdirCommand = Command(
    name: "mkdir",
    usage: "mkdir <tab-id> <path>     Create a directory in the Xcode project",
    minArgs: 2
  ) { args in
    callToolRequest(
      tool: XcodeTool.makeDir,
      arguments: ["tabIdentifier": .string(args[0]), "directoryPath": .string(args[1])]
    )
  }

  static let rmCommand = Command(
    name: "rm",
    usage: "rm <tab-id> <path>        Remove a file or directory from the Xcode project",
    minArgs: 2
  ) { args in
    callToolRequest(
      tool: XcodeTool.removeFile,
      arguments: ["tabIdentifier": .string(args[0]), "path": .string(args[1])]
    )
  }

  static let mvCommand = Command(
    name: "mv",
    usage: "mv <tab-id> <src> <dst>   Move or rename a file in the Xcode project",
    minArgs: 3
  ) { args in
    callToolRequest(
      tool: XcodeTool.moveFile,
      arguments: [
        "tabIdentifier": .string(args[0]),
        "sourcePath": .string(args[1]),
        "destinationPath": .string(args[2])
      ]
    )
  }

  static let writeCommand = Command(
    name: "write",
    usage: "write <tab-id> <path> <content>  Create or overwrite a file",
    minArgs: 3
  ) { args in
    callToolRequest(
      tool: XcodeTool.writeFile,
      arguments: [
        "tabIdentifier": .string(args[0]),
        "filePath": .string(args[1]),
        "content": .string(args[2])
      ]
    )
  }

  static let updateCommand = Command(
    name: "update",
    usage: "update <tab-id> <path> <old> <new>  Replace text in a file",
    minArgs: 4
  ) { args in
    callToolRequest(
      tool: XcodeTool.updateFile,
      arguments: [
        "tabIdentifier": .string(args[0]),
        "filePath": .string(args[1]),
        "oldString": .string(args[2]),
        "newString": .string(args[3])
      ]
    )
  }

  static let refreshIssuesCommand = Command(
    name: "refresh-issues",
    usage: "refresh-issues <tab-id> <file>  Refresh compiler diagnostics for a file",
    minArgs: 2
  ) { args in
    callToolRequest(
      tool: XcodeTool.refreshIssues,
      arguments: ["tabIdentifier": .string(args[0]), "filePath": .string(args[1])]
    )
  }

  static let execCommand = Command(
    name: "exec",
    usage: "exec <tab-id> <file> <purpose> <code>  Execute a Swift code snippet",
    minArgs: 4
  ) { args in
    callToolRequest(
      tool: XcodeTool.executeSnippet,
      arguments: [
        "tabIdentifier": .string(args[0]),
        "sourceFilePath": .string(args[1]),
        "purpose": .string(args[2]),
        "codeSnippet": .string(args[3])
      ]
    )
  }

  static let previewCommand = Command(
    name: "preview",
    usage: "preview <tab-id> <file> [index]  Render a SwiftUI preview",
    minArgs: 2
  ) { args in
    var toolArgs: JSONValue = [
      "tabIdentifier": .string(args[0]),
      "sourceFilePath": .string(args[1])
    ]
    if args.count >= 3, let idx = Int(args[2]), var obj = toolArgs.objectValue {
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

  // MARK: - Helper

  private static func callToolRequest(tool: String, arguments: JSONValue) -> LocalRPCRequest {
    let params = CallToolParams(tool: tool, arguments: arguments)
    let paramsData = (try? JSONEncoder().encode(params)) ?? Data()
    let paramsJSON = (try? JSONDecoder().decode(JSONValue.self, from: paramsData)) ?? .null
    return LocalRPCRequest(method: LocalRPCMethod.callTool, params: paramsJSON)
  }
}
