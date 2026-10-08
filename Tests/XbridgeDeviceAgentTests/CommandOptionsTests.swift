import Testing

@testable import XbridgeDeviceAgent

@Suite struct CommandOptionsTests {
  @Test func parsesAllOptionsAndJoinsGoalWords() throws {
    let options = try DeviceAgentCommandOptions(arguments: [
      "Session", "open", "search", "--act", "--bundle-id", "com.example",
      "--steps", "5", "--min-confidence", "0.75", "--text", "hello world",
      "--text", "second", "--trace", "/tmp/trace"
    ]).configuration
    #expect(options.sessionKey == "Session")
    #expect(options.goal == "open search")
    #expect(options.act)
    #expect(options.bundleIdentifier == "com.example")
    #expect(options.maxSteps == 5)
    #expect(options.minimumConfidence == 0.75)
    #expect(options.textCandidates == ["hello world", "second"])
    #expect(options.traceDirectory == "/tmp/trace")
  }

  @Test func rejectsUnknownAndInvalidOptions() {
    #expect(throws: AgentError.self) {
      try DeviceAgentCommandOptions(arguments: ["Session", "goal", "--unknown"])
    }
    #expect(throws: AgentError.self) {
      try DeviceAgentCommandOptions(arguments: ["Session", "goal", "--steps", "zero"])
    }
    #expect(throws: AgentError.self) {
      try DeviceAgentCommandOptions(arguments: ["Session", "goal", "--min-confidence", "2"])
    }
  }
}
