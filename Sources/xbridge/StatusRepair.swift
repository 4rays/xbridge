import Foundation

enum StatusRepairError: LocalizedError {
  case usage
  case invalidProject(String)
  case workspaceID
  case missingHelper(String)
  case refused(String)

  var errorDescription: String? {
    switch self {
    case .usage: "usage: xbridge status --fix [--project <project-root>]"
    case .invalidProject(let path): "Project root is not a directory: \(path)"
    case .workspaceID:
      "status --fix needs a project root, not a workspace ID; use --project <project-root>"
    case .missingHelper(let path): "xbridge-allow is missing alongside xbridge: \(path)"
    case .refused(let message): "Access repair refused: \(message)"
    }
  }
}

/// UI repair runs in the user-facing CLI, never in the background daemon.
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

  static func allow(projectPath: String) throws -> String {
    let cli = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath()
    let helper = cli.deletingLastPathComponent().appendingPathComponent("xbridge-allow")
    guard FileManager.default.isExecutableFile(atPath: helper.path) else {
      throw StatusRepairError.missingHelper(helper.path)
    }

    let process = Process()
    process.executableURL = helper
    process.arguments = ["--allow", projectPath]
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let output =
      String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error =
      String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw StatusRepairError.refused(
        "\(projectPath): \(error.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
