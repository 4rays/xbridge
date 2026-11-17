import Testing
import XbridgeCore

@testable import xbridge

@Suite("Device install command")
struct DeviceInstallCommandTests {
  private func toolArguments(_ args: [String]) throws -> JSONValue? {
    let request = try Commands.deviceInstallCommand.build(args)
    #expect(request.params?["tool"]?.stringValue == XcodeTool.deviceInteractionInstallAndRun)
    return request.params?["arguments"]
  }

  @Test("Sends only the session key when no launch flags are given")
  func keyOnly() throws {
    let arguments = try toolArguments(["Verify Login Flow"])

    #expect(arguments == .object(["interactionSessionKey": .string("Verify Login Flow")]))
  }

  @Test("Keeps scheme values by adding $(inherited) first")
  func inheritsByDefault() throws {
    let arguments = try toolArguments([
      "Verify Login Flow", "--arg", "--reset-state", "--env", "DEBUG_MODE=1"
    ])

    #expect(
      arguments?["commandLineArguments"]
        == .array([.string("$(inherited)"), .string("--reset-state")]))

    #expect(
      arguments?["environmentVariables"]
        == .object(["$(inherited)": .string(""), "DEBUG_MODE": .string("1")]))
  }

  @Test("Keeps an explicit $(inherited) position and does not add it again")
  func explicitInheritedPosition() throws {
    let arguments = try toolArguments(["Key", "--arg", "-first", "--arg=$(inherited)"])

    #expect(
      arguments?["commandLineArguments"] == .array([.string("-first"), .string("$(inherited)")]))

    #expect(arguments?["environmentVariables"] == nil)
  }

  @Test("--no-inherit replaces scheme values, also when no values are given")
  func noInherit() throws {
    let arguments = try toolArguments(["--no-inherit", "Key", "--env=URL=https://a.test/?x=1"])

    #expect(arguments?["interactionSessionKey"] == .string("Key"))
    #expect(arguments?["commandLineArguments"] == .array([]))
    #expect(arguments?["environmentVariables"] == .object(["URL": .string("https://a.test/?x=1")]))
  }

  @Test("Accepts an empty environment value")
  func emptyEnvironmentValue() throws {
    let arguments = try toolArguments(["Key", "--env", "EMPTY="])

    #expect(arguments?["environmentVariables"]?["EMPTY"] == .string(""))
  }

  @Test(
    "Rejects invalid input",
    arguments: [
      (["Key", "--env", "NOEQUALS"], DeviceInstallFlagError.invalidEnvironment("NOEQUALS")),
      (["Key", "--env", "=1"], .invalidEnvironment("=1")),
      (["Key", "--arg"], .missingValue("--arg")),
      (["Key", "--reset-state"], .unknownFlag("--reset-state")),
      (["Key", "Other"], .unexpectedArgument("Other")),
      (["--no-inherit"], .missingSessionKey)
    ]
  )
  func rejectsInvalidInput(args: [String], expected: DeviceInstallFlagError) {
    #expect(throws: expected) {
      _ = try Commands.deviceInstallCommand.build(args)
    }
  }
}
