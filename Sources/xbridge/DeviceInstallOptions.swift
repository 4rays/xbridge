import Foundation
import XbridgeCore

/// Parses `device-install <key> [--arg <value>]... [--env KEY=VALUE]... [--no-inherit]`.
///
/// Scheme-provided values are kept by default through Xcode's `$(inherited)` token.
/// `--no-inherit` replaces them for this run.
struct DeviceInstallOptions {
  static let inheritedToken = "$(inherited)"

  let sessionKey: String
  let arguments: [String]
  let environment: [(key: String, value: String)]
  let inheritsSchemeValues: Bool

  init(parsing args: [String]) throws {
    var sessionKey: String?
    var arguments: [String] = []
    var environment: [(key: String, value: String)] = []
    var inherits = true
    var index = args.startIndex

    func value(for flag: String) throws -> String {
      let valueIndex = args.index(after: index)
      guard valueIndex < args.endIndex else { throw DeviceInstallFlagError.missingValue(flag) }
      index = valueIndex
      return args[valueIndex]
    }

    while index < args.endIndex {
      let token = args[index]

      switch token {
      case "--arg":
        arguments.append(try value(for: "--arg"))

      case _ where token.hasPrefix("--arg="):
        arguments.append(String(token.dropFirst("--arg=".count)))

      case "--env":
        environment.append(try Self.environmentPair(try value(for: "--env")))

      case _ where token.hasPrefix("--env="):
        environment.append(try Self.environmentPair(String(token.dropFirst("--env=".count))))

      case "--no-inherit":
        inherits = false

      case _ where token.hasPrefix("--"):
        throw DeviceInstallFlagError.unknownFlag(token)

      default:
        guard sessionKey == nil else { throw DeviceInstallFlagError.unexpectedArgument(token) }
        sessionKey = token
      }

      index = args.index(after: index)
    }

    guard let sessionKey else { throw DeviceInstallFlagError.missingSessionKey }

    self.sessionKey = sessionKey
    self.arguments = arguments
    self.environment = environment
    self.inheritsSchemeValues = inherits
  }

  /// Tool arguments for `DeviceInteractionInstallAndRun`.
  /// With no `--arg`, `--env`, or `--no-inherit`, only the session key is sent,
  /// so the scheme's arguments and environment stay unchanged.
  var toolArguments: [String: JSONValue] {
    var dict: [String: JSONValue] = ["interactionSessionKey": .string(sessionKey)]

    if !arguments.isEmpty || !inheritsSchemeValues {
      var values = arguments

      if inheritsSchemeValues, !values.contains(Self.inheritedToken) {
        values.insert(Self.inheritedToken, at: 0)
      }

      dict["commandLineArguments"] = .array(values.map(JSONValue.string))
    }

    if !environment.isEmpty || !inheritsSchemeValues {
      var values: [String: JSONValue] = [:]

      if inheritsSchemeValues {
        values[Self.inheritedToken] = .string("")
      }

      for (key, value) in environment {
        values[key] = .string(value)
      }

      dict["environmentVariables"] = .object(values)
    }

    return dict
  }

  private static func environmentPair(_ raw: String) throws -> (key: String, value: String) {
    guard let separator = raw.firstIndex(of: "="), separator != raw.startIndex else {
      throw DeviceInstallFlagError.invalidEnvironment(raw)
    }

    return (String(raw[..<separator]), String(raw[raw.index(after: separator)...]))
  }
}

enum DeviceInstallFlagError: LocalizedError, Equatable {
  case missingSessionKey
  case missingValue(String)
  case invalidEnvironment(String)
  case unknownFlag(String)
  case unexpectedArgument(String)

  var errorDescription: String? {
    switch self {
    case .missingSessionKey:
      return "'device-install' requires a session key"

    case .missingValue(let flag):
      return "'device-install \(flag)' requires a value"

    case .invalidEnvironment(let raw):
      return "'device-install --env' expects KEY=VALUE, got '\(raw)'"

    case .unknownFlag(let flag):
      return "'device-install' does not know '\(flag)'; use --arg=\(flag) to pass it to the app"

    case .unexpectedArgument(let argument):
      return "'device-install' takes one session key; unexpected '\(argument)'"
    }
  }
}
