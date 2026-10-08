import Foundation

public struct DeviceAgentCommandOptions: Sendable {
  public let configuration: AgentConfiguration

  public init(arguments: [String]) throws {
    guard arguments.count >= 2 else {
      throw AgentError.invalidConfiguration(
        "usage: xbridge device-agent <session-key> <goal> [--act] [--bundle-id <id>] [--steps <n>] [--min-confidence <p>] [--text <value>]... [--trace <directory>]"
      )
    }
    let sessionKey = arguments[0]
    var goalParts: [String] = []
    var act = false
    var bundleIdentifier: String?
    var steps = 12
    var minimumConfidence = 0.5
    var textCandidates: [String] = []
    var traceDirectory: String?
    var index = 1

    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--act":
        act = true
        index += 1
      case "--bundle-id", "--steps", "--min-confidence", "--text", "--trace":
        guard index + 1 < arguments.count else {
          throw AgentError.invalidConfiguration("Missing value for \(argument)")
        }
        let value = arguments[index + 1]
        switch argument {
        case "--bundle-id": bundleIdentifier = value
        case "--steps":
          guard let parsed = Int(value) else {
            throw AgentError.invalidConfiguration("--steps must be an integer")
          }
          steps = parsed
        case "--min-confidence":
          guard let parsed = Double(value) else {
            throw AgentError.invalidConfiguration("--min-confidence must be a number")
          }
          minimumConfidence = parsed
        case "--text": textCandidates.append(value)
        case "--trace": traceDirectory = value
        default: break
        }
        index += 2
      default:
        guard !argument.hasPrefix("--") else {
          throw AgentError.invalidConfiguration("Unknown device-agent option: \(argument)")
        }
        goalParts.append(argument)
        index += 1
      }
    }

    self.configuration = try AgentConfiguration(
      sessionKey: sessionKey,
      goal: goalParts.joined(separator: " "),
      act: act,
      bundleIdentifier: bundleIdentifier,
      maxSteps: steps,
      minimumConfidence: minimumConfidence,
      textCandidates: textCandidates,
      traceDirectory: traceDirectory
    )
  }
}
