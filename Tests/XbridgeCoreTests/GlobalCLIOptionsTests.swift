import Testing
@testable import XbridgeCore

@Suite("GlobalCLIOptions")
struct GlobalCLIOptionsTests {
  @Test("Extracts --xcode-path from the prefix before the command")
  func extractsFromPrefix() {
    let result = GlobalCLIOptions.extractXcodePath(
      from: ["--xcode-path", "/Applications/Xcode.app", "status"]
    )
    #expect(result.path == "/Applications/Xcode.app")
    #expect(result.remaining == ["status"])
  }

  @Test("Leaves --xcode-path after the command as a positional argument")
  func leavesPositionalXcodePath() {
    let result = GlobalCLIOptions.extractXcodePath(
      from: ["grep", "--xcode-path", "windowtab1"]
    )
    #expect(result.path == nil)
    #expect(result.remaining == ["grep", "--xcode-path", "windowtab1"])
  }

  @Test("Does not consume a later --xcode-path used as a grep pattern")
  func prefixPathDoesNotConsumeLaterPattern() {
    let result = GlobalCLIOptions.extractXcodePath(
      from: ["--xcode-path", "/Applications/Xcode.app", "grep", "--xcode-path", "windowtab1"]
    )
    #expect(result.path == "/Applications/Xcode.app")
    #expect(result.remaining == ["grep", "--xcode-path", "windowtab1"])
  }

  @Test("Leaves a trailing --xcode-path with no value")
  func trailingFlagWithoutValue() {
    let result = GlobalCLIOptions.extractXcodePath(from: ["--xcode-path"])
    #expect(result.path == nil)
    #expect(result.remaining == ["--xcode-path"])
  }

  @Test("Extracts --workspace from the prefix")
  func extractsWorkspaceFromPrefix() {
    let result = GlobalCLIOptions.extract(
      from: ["--workspace", "workspace1", "build"]
    )
    #expect(result.workspace == "workspace1")
    #expect(result.remaining == ["build"])
  }

  @Test("Extracts --workspace after the command")
  func extractsWorkspaceAfterCommand() {
    let result = GlobalCLIOptions.extract(
      from: ["build", "--workspace", "workspace1"]
    )
    #expect(result.workspace == "workspace1")
    #expect(result.remaining == ["build"])
  }

  @Test("Leaves a later --workspace used as a positional after stripping the first")
  func stripsOnlyFirstWorkspace() {
    let result = GlobalCLIOptions.extract(
      from: ["grep", "--workspace", "workspace1", "--workspace"]
    )
    #expect(result.workspace == "workspace1")
    #expect(result.remaining == ["grep", "--workspace"])
  }
}
