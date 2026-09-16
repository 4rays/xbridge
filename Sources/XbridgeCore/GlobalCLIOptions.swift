/// Global flags that must appear before the command name, plus
/// `--workspace` which may also appear among command arguments.
public enum GlobalCLIOptions {
  public struct Extracted: Sendable {
    public let xcodePath: String?
    public let workspace: String?
    public let remaining: [String]
  }

  /// Parses `--xcode-path <path>` from the option prefix only.
  /// Later occurrences stay in `remaining` as positional arguments.
  public static func extractXcodePath(from arguments: [String]) -> (path: String?, remaining: [String]) {
    let extracted = extract(from: arguments)
    return (extracted.xcodePath, extracted.remaining)
  }

  /// Parses `--xcode-path` from the prefix and `--workspace` from prefix or
  /// among remaining arguments.
  public static func extract(from arguments: [String]) -> Extracted {
    var index = arguments.startIndex
    var xcodePath: String?
    var workspace: String?

    while index < arguments.endIndex {
      let argument = arguments[index]
      if argument == "--xcode-path" {
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { break }
        xcodePath = arguments[valueIndex]
        index = arguments.index(after: valueIndex)
        continue
      }
      if argument == "--workspace" {
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { break }
        workspace = arguments[valueIndex]
        index = arguments.index(after: valueIndex)
        continue
      }
      break
    }

    var remaining = Array(arguments[index...])
    if workspace == nil {
      let stripped = stripWorkspace(from: remaining)
      workspace = stripped.workspace
      remaining = stripped.remaining
    }
    return Extracted(xcodePath: xcodePath, workspace: workspace, remaining: remaining)
  }

  /// Removes a `--workspace <id>` pair from command arguments.
  public static func stripWorkspace(from arguments: [String]) -> (workspace: String?, remaining: [String]) {
    var workspace: String?
    var remaining: [String] = []
    remaining.reserveCapacity(arguments.count)
    var index = arguments.startIndex
    while index < arguments.endIndex {
      if arguments[index] == "--workspace" {
        let valueIndex = arguments.index(after: index)
        if valueIndex < arguments.endIndex, workspace == nil {
          workspace = arguments[valueIndex]
          index = arguments.index(after: valueIndex)
          continue
        }
      }
      remaining.append(arguments[index])
      index = arguments.index(after: index)
    }
    return (workspace, remaining)
  }
}
