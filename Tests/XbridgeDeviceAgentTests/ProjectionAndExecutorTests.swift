import Foundation
import Testing

@testable import XbridgeDeviceAgent

@Suite struct ProjectionAndExecutorTests {
  @Test func projectionIsBoundedAndExcludesSensitiveExecutorData() throws {
    let observation = try TestSupport.observation()
    let configuration = try AgentConfiguration(
      sessionKey: "Test",
      goal: "Enter Kai in the display name",
      textCandidates: ["Kai"]
    )
    let history = (0..<12).map { index in
      AgentHistoryEntry(
        operation: .tap, target: "target \(index)", textLength: nil, screenChanged: true)
    }
    let plan = try StateProjection.build(
      observation: observation,
      configuration: configuration,
      history: history,
      model: "jev-latest"
    )
    let data = try JSONEncoder().encode(plan.request)
    let encoded = String(decoding: data, as: UTF8.self)

    #expect(plan.request.questions["operation"]?.criteria["TYPE_TEXT"] != nil)
    #expect(plan.request.questions["text_value"]?.criteria.keys.contains("NONE") == true)
    #expect(!encoded.contains("/tmp/"))
    #expect(!encoded.contains("hitPoint"))
    #expect(!encoded.contains("•••••"))
    #expect(plan.request.state["recent_actions"]?.arrayValue?.count == 8)
    #expect(data.count <= AgentLimits.maximumEncodedRequestBytes)
    #expect(!plan.tapTargets.values.contains { $0.role == "StaticText" })
  }

  @Test func secureFocusedFieldRemovesTypeText() throws {
    let source = """
      Application bundle identifier: com.example
       Window, {{0.0, 0.0}, {100.0, 200.0}}, hitPoint: {50.0, 100.0}
        SecureTextField, {{10.0, 20.0}, {80.0, 40.0}}, label: 'Password', value: •••, Focused, Secure, Editable, hitPoint: {50.0, 40.0}
      """
    let observation = try ObservationFactory.make(
      decoded: DecodedDeviceHubResult(
        applicationState: "RunningForeground",
        hierarchyPath: "/tmp/h.txt",
        screenshotPath: nil,
        logsPath: nil
      ),
      hierarchy: source
    )
    let plan = try StateProjection.build(
      observation: observation,
      configuration: AgentConfiguration(sessionKey: "Test", goal: "Enter secret"),
      history: [],
      model: "jev-latest"
    )
    #expect(plan.request.questions["operation"]?.criteria["TYPE_TEXT"] == nil)
    #expect(plan.request.questions["text_value"] == nil)
  }

  @Test func exactTextCandidatesPreserveExplicitValuesAndRejectControls() throws {
    let values = try TextCandidates.extract(
      goal: "Enter José Alvarez now", explicit: ["José Alvarez", "José Alvarez"])
    #expect(values.first == "José Alvarez")
    #expect(values.filter { $0 == "José Alvarez" }.count == 1)
    #expect(values.contains("Enter José Alvarez now"))
    #expect(throws: AgentError.self) {
      try TextCandidates.extract(goal: "safe", explicit: ["bad\u{0000}value"])
    }
  }

  @Test func targetResolutionRequiresUniqueFreshSemantics() throws {
    let observation = try TestSupport.observation()
    let saves = observation.elements.filter { $0.label == "Save" }
    let primary = try #require(saves.first { $0.identifier == "save-primary" })
    #expect(TargetResolver.resolve(primary.identity, in: observation)?.identifier == "save-primary")

    let ambiguousIdentity = SemanticIdentity(
      path: "missing",
      identifier: nil,
      role: "Button",
      label: "Save",
      value: nil,
      parentRole: "ScrollView"
    )
    #expect(TargetResolver.resolve(ambiguousIdentity, in: observation) == nil)
  }

  @Test func commandsUseFreshGeometryAndExactText() throws {
    let observation = try TestSupport.observation()
    let save = try #require(observation.elements.first { $0.identifier == "save-primary" })
    #expect(try DeviceCommandBuilder.tap(save) == "t 80.0 374.0")
    let field = try #require(observation.focusedField)
    #expect(
      try DeviceCommandBuilder.typeText("Kai Smith", field: field)
        == "sender keyboard kbd Kai Smith")
    let scroll = try DeviceCommandBuilder.scroll(
      .scrollDown, region: observation.scrollRegions.first, observation: observation)
    #expect(scroll.contains(" f "))
    #expect(throws: AgentError.self) {
      try DeviceCommandBuilder.tap(
        try #require(observation.elements.first { $0.identifier == "delete" }))
    }
  }

  @Test func readbackResolutionAllowsTheExpectedFieldValueToChange() throws {
    let before = try TestSupport.observation()
    let identity = try #require(before.focusedField).identity
    let changedHierarchy = before.hierarchy.replacingOccurrences(
      of: "value: Kai", with: "value: Kai Smith")
    let after = try ObservationFactory.make(
      decoded: DecodedDeviceHubResult(
        applicationState: "RunningForeground",
        hierarchyPath: "/tmp/after.txt",
        screenshotPath: nil,
        logsPath: nil
      ),
      hierarchy: changedHierarchy
    )
    #expect(TargetResolver.resolve(identity, in: after) == nil)
    #expect(TargetResolver.resolveFieldForReadback(identity, in: after)?.value == "Kai Smith")
  }
}
