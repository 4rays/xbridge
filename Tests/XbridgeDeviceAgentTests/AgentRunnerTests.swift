import Foundation
import Testing

@testable import XbridgeDeviceAgent

private actor FakeDevice: DeviceHubControlling {
  private var observations: [Result<DeviceObservation, AgentError>]
  private var executionResults: [Result<DeviceObservation, AgentError>]
  private(set) var commands: [String] = []

  init(observations: [DeviceObservation], executionResults: [DeviceObservation] = []) {
    self.observations = observations.map(Result.success)
    self.executionResults = executionResults.map(Result.success)
  }

  init(
    observationResults: [Result<DeviceObservation, AgentError>],
    executionResults: [Result<DeviceObservation, AgentError>] = []
  ) {
    self.observations = observationResults
    self.executionResults = executionResults
  }

  func observe(sessionKey: String, bundleIdentifier: String?) async throws -> DeviceObservation {
    guard !observations.isEmpty else { throw AgentError.observation("No fake observation") }
    return try observations.removeFirst().get()
  }

  func execute(
    sessionKey: String,
    command: String,
    bundleIdentifier: String?
  ) async throws -> DeviceObservation {
    commands.append(command)
    guard !executionResults.isEmpty else { throw AgentError.ambiguousMutation("No fake result") }
    return try executionResults.removeFirst().get()
  }
}

private actor FakePolicy: AgentPolicyEvaluating {
  private var decisions: [AgentDecision]

  init(_ decisions: [AgentDecision]) { self.decisions = decisions }

  func decide(
    observation: DeviceObservation,
    configuration: AgentConfiguration,
    history: [AgentHistoryEntry]
  ) async throws -> AgentDecision {
    guard !decisions.isEmpty else { throw AgentError.invalidPolicyResponse("No fake decision") }
    return decisions.removeFirst()
  }
}

private struct ImmediateClock: AgentClock {
  func now() -> Date { Date(timeIntervalSince1970: 1) }
  func sleep(for duration: Duration) async throws {}
}

private struct ThrowingPolicy: AgentPolicyEvaluating {
  let error: AgentError

  func decide(
    observation: DeviceObservation,
    configuration: AgentConfiguration,
    history: [AgentHistoryEntry]
  ) async throws -> AgentDecision {
    throw error
  }
}

private struct BlockingPolicy: AgentPolicyEvaluating {
  func decide(
    observation: DeviceObservation,
    configuration: AgentConfiguration,
    history: [AgentHistoryEntry]
  ) async throws -> AgentDecision {
    try await Task.sleep(for: .seconds(60))
    throw AgentError.invalidPolicyResponse("unreachable")
  }
}

private struct AlwaysVerifier: AgentOutcomeVerifying {
  func verify(goal: String, observation: DeviceObservation) async throws -> Bool { true }
}

private actor RecordingTrace: AgentTracing {
  nonisolated let directory: String? = "/tmp/fake-trace"
  private(set) var events: [String] = []

  func record<Value: Encodable & Sendable>(_ name: String, value: Value) async throws {
    events.append(name)
  }

  func copyArtifact(at path: String, name: String) async throws {
    events.append("artifact:\(name)")
  }
}

@Suite struct AgentRunnerTests {
  @Test func previewMakesOneDecisionAndNeverMutates() async throws {
    let observation = try TestSupport.observation()
    let device = FakeDevice(observations: [observation])
    let runner = DeviceAgentRunner(
      device: device,
      policy: FakePolicy([doneDecision()]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    )
    let result = await runner.run(
      configuration: try AgentConfiguration(sessionKey: "Test", goal: "Finish")
    )
    #expect(result.outcome == .preview)
    #expect(result.decisions == 1)
    #expect(await device.commands.isEmpty)
  }

  @Test func activeRunUsesFreshGeometryAndAcceptsOnlyStableDone() async throws {
    let initial = try TestSupport.observation(fingerprintOverride: "A")
    let post = try TestSupport.observation(fingerprintOverride: "B")
    let final = try TestSupport.observation(fingerprintOverride: "C")
    let back = try #require(initial.elements.first { $0.identifier == "back" })
    let notifications = try #require(
      initial.elements.first { $0.identifier == "notifications" })
    let tapBack = AgentDecision(
      operation: .tap,
      operationAnswer: TestSupport.answer(choice: "TAP", keys: ["TAP"]),
      targetAnswer: TestSupport.answer(choice: "tap_0", keys: ["tap_0"]),
      target: back.identity,
      confidence: 1
    )
    let tapNotifications = AgentDecision(
      operation: .tap,
      operationAnswer: TestSupport.answer(choice: "TAP", keys: ["TAP"]),
      targetAnswer: TestSupport.answer(choice: "tap_0", keys: ["tap_0"]),
      target: notifications.identity,
      confidence: 1
    )
    let device = FakeDevice(
      observations: [initial, initial, post, final], executionResults: [post, final])
    let trace = RecordingTrace()
    let runner = DeviceAgentRunner(
      device: device,
      policy: FakePolicy([tapBack, tapNotifications, doneDecision()]),
      trace: trace,
      clock: ImmediateClock()
    )
    let result = await runner.run(
      configuration: try AgentConfiguration(sessionKey: "Test", goal: "Tap back", act: true)
    )
    #expect(result.outcome == .modelDone)
    #expect(result.executedSteps == 2)
    #expect(await device.commands == ["t 38.0 88.0", "t 341.0 314.0"])
    #expect(result.message.contains("not independently verified"))
    let events = await trace.events
    #expect(events.contains("action-1"))
    #expect(events.contains("action-1-timing"))
    #expect(events.contains("post-action-1"))
    #expect(events.contains("outcome"))
  }

  @Test func lowConfidenceStopsBeforeFreshObservationOrMutation() async throws {
    let observation = try TestSupport.observation()
    let low = AgentDecision(
      operation: .tap,
      operationAnswer: TestSupport.answer(choice: "TAP", keys: ["TAP"], confidence: 0.2),
      confidence: 0.2
    )
    let device = FakeDevice(observations: [observation])
    let runner = DeviceAgentRunner(
      device: device,
      policy: FakePolicy([low]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    )
    let result = await runner.run(
      configuration: try AgentConfiguration(
        sessionKey: "Test",
        goal: "Tap",
        act: true,
        minimumConfidence: 0.5
      )
    )
    #expect(result.outcome == .lowConfidence)
    #expect(await device.commands.isEmpty)
  }

  @Test func lowConfidenceWaitReobservesAndCanThenComplete() async throws {
    let observation = try TestSupport.observation(fingerprintOverride: "stable")
    let trace = RecordingTrace()
    let result = await DeviceAgentRunner(
      device: FakeDevice(observations: [observation, observation, observation]),
      policy: FakePolicy([simpleDecision(.wait, confidence: 0.2), doneDecision()]),
      trace: trace,
      clock: ImmediateClock()
    ).run(
      configuration: try AgentConfiguration(
        sessionKey: "Test", goal: "Wait for completion", act: true, minimumConfidence: 0.5)
    )

    #expect(result.outcome == .modelDone)
    #expect(result.executedSteps == 1)
    #expect(await trace.events.contains("fallback-wait-1"))
  }

  @Test func lowConfidenceTerminalDecisionsHaveABoundedFallback() async throws {
    let observation = try TestSupport.observation(fingerprintOverride: "stable")
    let lowDone = simpleDecision(.done, confidence: 0.2)
    let result = await DeviceAgentRunner(
      device: FakeDevice(observations: [observation, observation, observation]),
      policy: FakePolicy([lowDone, lowDone, lowDone]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    ).run(
      configuration: try AgentConfiguration(
        sessionKey: "Test", goal: "Finish", act: true, minimumConfidence: 0.5)
    )

    #expect(result.outcome == .lowConfidence)
    #expect(result.executedSteps == 2)
    #expect(result.decisions == 3)
  }

  @Test func repeatedStaleTargetsStopWithoutMutation() async throws {
    let observation = try TestSupport.observation()
    let missing = SemanticIdentity(
      path: "root/Button[999]",
      identifier: "missing",
      role: "Button",
      label: "Gone",
      value: nil,
      parentRole: "Window"
    )
    let decision = AgentDecision(
      operation: .tap,
      operationAnswer: TestSupport.answer(choice: "TAP", keys: ["TAP"]),
      targetAnswer: TestSupport.answer(choice: "tap_0", keys: ["tap_0"]),
      target: missing,
      confidence: 1
    )
    let device = FakeDevice(observations: [observation, observation, observation, observation])
    let runner = DeviceAgentRunner(
      device: device,
      policy: FakePolicy([decision, decision, decision]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    )
    let result = await runner.run(
      configuration: try AgentConfiguration(sessionKey: "Test", goal: "Tap gone", act: true)
    )
    #expect(result.outcome == .unstableUI)
    #expect(await device.commands.isEmpty)
  }

  @Test func exactTextReadbackSucceedsWithoutRetyping() async throws {
    let before = try TestSupport.observation()
    let after = try TestSupport.observation(replacing: "value: Kai,", with: "value: Kai Smith,")
    let decision = textDecision("Kai Smith")
    let device = FakeDevice(observations: [before, before, after], executionResults: [after])
    let runner = DeviceAgentRunner(
      device: device,
      policy: FakePolicy([decision, doneDecision()]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    )
    let result = await runner.run(
      configuration: try AgentConfiguration(
        sessionKey: "Test", goal: "Enter Kai Smith", act: true, textCandidates: ["Kai Smith"])
    )
    #expect(result.outcome == .modelDone)
    #expect(await device.commands == ["sender keyboard kbd Kai Smith"])
  }

  @Test func unreadableTextStopsWithoutRetryingTheMutation() async throws {
    let observation = try TestSupport.observation()
    let device = FakeDevice(
      observations: Array(repeating: observation, count: 6),
      executionResults: [observation]
    )
    let runner = DeviceAgentRunner(
      device: device,
      policy: FakePolicy([textDecision("Kai Smith")]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    )
    let result = await runner.run(
      configuration: try AgentConfiguration(
        sessionKey: "Test", goal: "Enter Kai Smith", act: true, textCandidates: ["Kai Smith"])
    )
    #expect(result.outcome == .inputUnverified)
    #expect(await device.commands == ["sender keyboard kbd Kai Smith"])
  }

  @Test func sessionExpiryAndAmbiguousMutationMapToSafeTerminalOutcomes() async throws {
    let expired = DeviceAgentRunner(
      device: FakeDevice(observationResults: [.failure(.sessionExpired)]),
      policy: FakePolicy([]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    )
    let expiredResult = await expired.run(
      configuration: try AgentConfiguration(sessionKey: "Test", goal: "Observe", act: true)
    )
    #expect(expiredResult.outcome == .sessionExpired)

    let observation = try TestSupport.observation()
    let back = try #require(observation.elements.first { $0.identifier == "back" })
    let tap = AgentDecision(
      operation: .tap,
      operationAnswer: TestSupport.answer(choice: "TAP", keys: ["TAP"]),
      targetAnswer: TestSupport.answer(choice: "tap_0", keys: ["tap_0"]),
      target: back.identity,
      confidence: 1
    )
    let uncertain = FakeDevice(
      observationResults: [.success(observation), .success(observation)],
      executionResults: [.failure(.ambiguousMutation("uncertain"))]
    )
    let ambiguous = DeviceAgentRunner(
      device: uncertain,
      policy: FakePolicy([tap]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    )
    let ambiguousResult = await ambiguous.run(
      configuration: try AgentConfiguration(sessionKey: "Test", goal: "Tap", act: true)
    )
    #expect(ambiguousResult.outcome == .ambiguousMutation)
    #expect(await uncertain.commands.count == 1)
  }

  @Test func remainingTerminalGuardsStopSafely() async throws {
    let observation = try TestSupport.observation()

    let blocked = await DeviceAgentRunner(
      device: FakeDevice(observations: [observation]),
      policy: FakePolicy([simpleDecision(.blocked)]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    ).run(configuration: configuration())
    #expect(blocked.outcome == .blocked)

    let needsInput = await DeviceAgentRunner(
      device: FakeDevice(observations: [observation]),
      policy: FakePolicy([simpleDecision(.typeText)]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    ).run(configuration: configuration())
    #expect(needsInput.outcome == .needsInput)

    let stepLimit = await DeviceAgentRunner(
      device: FakeDevice(observations: [observation, observation]),
      policy: FakePolicy([simpleDecision(.wait), simpleDecision(.wait)]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    ).run(
      configuration: try AgentConfiguration(
        sessionKey: "Test", goal: "Wait", act: true, maxSteps: 1)
    )
    #expect(stepLimit.outcome == .stepLimit)

    let decisionLimit = await DeviceAgentRunner(
      device: FakeDevice(observations: [observation, observation]),
      policy: FakePolicy([simpleDecision(.wait)]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    ).run(
      configuration: try AgentConfiguration(
        sessionKey: "Test", goal: "Wait", act: true, maxSteps: 2, maxDecisions: 1)
    )
    #expect(decisionLimit.outcome == .decisionLimit)

    let invalidPolicy = await DeviceAgentRunner(
      device: FakeDevice(observations: [observation]),
      policy: ThrowingPolicy(error: .invalidPolicyResponse("bad choice")),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    ).run(configuration: configuration())
    #expect(invalidPolicy.outcome == .invalidPolicyResponse)

    let observationFailure = await DeviceAgentRunner(
      device: FakeDevice(observationResults: [.failure(.observation("unavailable"))]),
      policy: FakePolicy([]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    ).run(configuration: configuration())
    #expect(observationFailure.outcome == .observationFailure)
  }

  @Test func repeatedNoOpStopsBeforeAThirdMutation() async throws {
    let observation = try TestSupport.observation(fingerprintOverride: "same")
    let back = try #require(observation.elements.first { $0.identifier == "back" })
    let tap = AgentDecision(
      operation: .tap,
      operationAnswer: TestSupport.answer(choice: "TAP", keys: ["TAP"]),
      targetAnswer: TestSupport.answer(choice: "tap_0", keys: ["tap_0"]),
      target: back.identity,
      confidence: 1
    )
    let device = FakeDevice(
      observations: Array(repeating: observation, count: 4),
      executionResults: [observation, observation]
    )
    let result = await DeviceAgentRunner(
      device: device,
      policy: FakePolicy([tap, tap, tap]),
      trace: NullTraceWriter(),
      clock: ImmediateClock()
    ).run(configuration: configuration())
    #expect(result.outcome == .stuck)
    #expect(await device.commands.count == 2)
  }

  @Test func verifierTraceAndCancellationSeamsWork() async throws {
    let observation = try TestSupport.observation()
    let trace = RecordingTrace()
    let verified = await DeviceAgentRunner(
      device: FakeDevice(observations: [observation, observation]),
      policy: FakePolicy([doneDecision()]),
      trace: trace,
      clock: ImmediateClock(),
      verifier: AlwaysVerifier()
    ).run(configuration: configuration())
    #expect(verified.outcome == .verifiedSuccess)
    let events = await trace.events
    #expect(events.contains("configuration"))
    #expect(events.contains("observation-0"))
    #expect(events.contains("observation-0-timing"))
    #expect(events.contains("decision-1"))
    #expect(events.contains("outcome"))

    let task = Task {
      await DeviceAgentRunner(
        device: FakeDevice(observations: [observation]),
        policy: BlockingPolicy(),
        trace: NullTraceWriter(),
        clock: ImmediateClock()
      ).run(configuration: configuration())
    }
    await Task.yield()
    task.cancel()
    #expect(await task.value.outcome == .cancelled)
  }

  private func doneDecision() -> AgentDecision {
    AgentDecision(
      operation: .done,
      operationAnswer: TestSupport.answer(choice: "DONE", keys: ["DONE"]),
      confidence: 1
    )
  }

  private func textDecision(_ text: String) -> AgentDecision {
    AgentDecision(
      operation: .typeText,
      operationAnswer: TestSupport.answer(choice: "TYPE_TEXT", keys: ["TYPE_TEXT"]),
      targetAnswer: TestSupport.answer(choice: "text_0", keys: ["text_0"]),
      text: text,
      confidence: 1
    )
  }

  private func simpleDecision(_ operation: AgentOperation, confidence: Double = 1) -> AgentDecision
  {
    AgentDecision(
      operation: operation,
      operationAnswer: TestSupport.answer(
        choice: operation.rawValue, keys: [operation.rawValue], confidence: confidence),
      confidence: confidence
    )
  }

  private func configuration() -> AgentConfiguration {
    try! AgentConfiguration(sessionKey: "Test", goal: "Test", act: true)
  }
}
