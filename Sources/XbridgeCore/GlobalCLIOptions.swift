/// Global flags that must appear before the command name.
public enum GlobalCLIOptions {
  /// Parses `--xcode-path <path>` from the option prefix only.
  /// Later occurrences stay in `remaining` as positional arguments.
  public static func extractXcodePath(from arguments: [String]) -> (path: String?, remaining: [String]) {
    var index = arguments.startIndex
    var path: String?

    while index < arguments.endIndex {
      let argument = arguments[index]
      if argument == "--xcode-path" {
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { break }
        path = arguments[valueIndex]
        index = arguments.index(after: valueIndex)
        continue
      }
      break
    }

    return (path, Array(arguments[index...]))
  }
}
