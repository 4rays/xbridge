import Foundation

enum StatusRepairError: LocalizedError {
  case usage
  case invalidProject(String)
  case workspaceID
  case statusFailed(String)

  var errorDescription: String? {
    switch self {
    case .usage: "usage: xbridge status --fix [--project <project-root>]"
    case .invalidProject(let path): "Project root is not a directory: \(path)"
    case .workspaceID:
      "status --fix needs a project root, not a workspace ID; use --project <project-root>"

    case .statusFailed(let message): "Cannot read Xcode MCP server status: \(message)"
    }
  }
}

/// Read-only permission discovery. Approval is left to the user in their terminal.
enum StatusRepair {
  static func projectPath(from args: [String]) throws -> String {
    let path: String
    if args == ["--fix"] {
      path = FileManager.default.currentDirectoryPath
    } else if args.count == 3, args[0] == "--fix", args[1] == "--project" {
      path = args[2]
    } else {
      throw StatusRepairError.usage
    }

    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw StatusRepairError.invalidProject(normalized)
    }
    return normalized
  }

  static func status(xcodePath: String?) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["mcp-server", "status", "--format", "json"]

    if let xcodePath {
      var environment = ProcessInfo.processInfo.environment
      environment["DEVELOPER_DIR"] = xcodePath
      process.environment = environment
    }

    let stdout = Pipe()
    process.standardOutput = stdout
    try process.run()
    let output =
      String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw StatusRepairError.statusFailed(
        "xcrun mcp-server exited with status \(process.terminationStatus). Requires Xcode 27 or later."
      )
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func instructions(projectPath: String) -> String {
    """
    No permissions were changed. Ask the user to run approval commands in their terminal.
    From the status above, verify the pending agent is the intended xbridged executable
    and the pending folder is the intended project (project root: \(projectPath)).
    Replace <request-id> with each matching pending request's ID, then run:

      sudo xcrun mcp-server approve <request-id> --for-24-hours

    Agent and folder requests may need separate approvals. Re-read status after each approval.
    --always is available only for signed agents and folders, not unsigned agents.
    If no matching request is pending, run open-workspace for the intended project first.
    After approval, retry the original workspace operation to confirm access.
    """
  }
}
