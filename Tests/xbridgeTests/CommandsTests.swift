import Foundation
import Testing
import XbridgeCore
import XbridgeDeviceAgent

@testable import xbridge

@Suite struct CommandsTests {
  @Test(
    "low-level Device Hub commands preserve MCP contracts",
    arguments: [
      (
        "device-start", ["Session", "Device"], XcodeTool.deviceInteractionStartWorkspaceSession,
        ["sessionIdentifier", "deviceIdentifier"]
      ),
      (
        "device-session", ["Device", "Session"], XcodeTool.deviceInteractionStartSession,
        ["deviceIdentifier", "sessionIdentifier"]
      ),
      (
        "device-end", ["Session"], XcodeTool.deviceInteractionEndSession,
        ["interactionSessionKey"]
      ),
      (
        "device-install", ["Session"], XcodeTool.deviceInteractionInstallAndRun,
        ["interactionSessionKey"]
      ),
      (
        "device-interact", ["Session", "t 1 2", "com.example"],
        XcodeTool.deviceInteractionSynthesize,
        ["interactSessionKey", "interactionCommand", "activationBundleId"]
      )
    ]
  )
  func preservesContract(
    name: String,
    arguments: [String],
    expectedTool: String,
    expectedKeys: [String]
  ) throws {
    let command = try #require(Commands.find(named: name))
    let request = try command.build(arguments)
    let paramsData = try JSONEncoder().encode(try #require(request.params))
    let params = try JSONDecoder().decode(CallToolParams.self, from: paramsData)
    #expect(params.tool == expectedTool)
    let keys = try #require(params.arguments.objectValue).keys
    #expect(Set(keys) == Set(expectedKeys))
  }

  @Test func deviceAgentProgressDescribesDecisionsWithoutPrintingTypedText() {
    let identity = SemanticIdentity(
      path: "0.1",
      identifier: "search",
      role: "SearchField",
      label: "Search",
      value: nil,
      parentRole: "Toolbar"
    )
    let answer = ChoiceAnswer(
      type: "choice",
      choice: "TYPE_TEXT",
      probabilities: ["TYPE_TEXT": 1],
      confidence: 0.92
    )
    let decision = AgentDecision(
      operation: .typeText,
      operationAnswer: answer,
      target: identity,
      text: "private value",
      confidence: 0.92
    )

    let decisionLine = DeviceAgentProgressFormatter.decision(
      name: "decision-2", decision: decision)
    let actionLine = DeviceAgentProgressFormatter.action(name: "action-2", decision: decision)

    #expect(decisionLine.contains("[jev 2] TYPE_TEXT"))
    #expect(decisionLine.contains("target=\"Search\""))
    #expect(decisionLine.contains("text_length=13"))
    #expect(actionLine.contains("[act 2] execute TYPE_TEXT"))
    #expect(!decisionLine.contains("private value"))
    #expect(!actionLine.contains("private value"))

    let fallbackLine = DeviceAgentProgressFormatter.fallbackWait(
      name: "fallback-wait-1",
      message: "Low-confidence WAIT (0.21); waiting for fresh evidence"
    )
    #expect(fallbackLine.contains("[fallback wait 1]"))
    #expect(fallbackLine.contains("waiting for fresh evidence"))
  }
}
