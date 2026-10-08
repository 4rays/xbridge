import Foundation

public struct DeviceAgentRunner<
  Device: DeviceHubControlling,
  Policy: AgentPolicyEvaluating,
  Trace: AgentTracing,
  Clock: AgentClock
>: Sendable {
  private static var maximumLowConfidenceFallbackWaits: Int { 2 }

  private let device: Device
  private let policy: Policy
  private let trace: Trace
  private let clock: Clock
  private let verifier: (any AgentOutcomeVerifying)?

  public init(
    device: Device,
    policy: Policy,
    trace: Trace,
    clock: Clock = ContinuousAgentClock(),
    verifier: (any AgentOutcomeVerifying)? = nil
  ) {
    self.device = device
    self.policy = policy
    self.trace = trace
    self.clock = clock
    self.verifier = verifier
  }

  public func run(configuration: AgentConfiguration) async -> AgentRunResult {
    var observation: DeviceObservation?
    var history: [AgentHistoryEntry] = []
    var decisions = 0
    var steps = 0
    var staleDecisions = 0
    var lastActionSignature: String?
    var repeatedNoOps = 0
    var lowConfidenceFallbackWaits = 0

    do {
      try await trace.record("configuration", value: configuration)
      observation = try await observe(configuration, index: 0)
      guard var current = observation else {
        return await result(
          .observationFailure, "No initial observation", nil, nil, steps, decisions)
      }

      while true {
        try Task.checkCancellation()
        guard decisions < configuration.maxDecisions else {
          return await result(
            .decisionLimit, "Decision budget exhausted", nil, current, steps, decisions)
        }
        let decision = try await policy.decide(
          observation: current,
          configuration: configuration,
          history: history
        )
        decisions += 1
        try await trace.record("decision-\(decisions)", value: decision)

        if !configuration.act {
          return await result(
            .preview, "Preview only; no interaction was sent", decision, current, steps, decisions)
        }

        if decision.confidence < configuration.minimumConfidence {
          switch decision.operation {
          case .tap, .typeText, .scrollUp, .scrollDown:
            return await result(
              .lowConfidence,
              "Mutation confidence \(decision.confidence) is below \(configuration.minimumConfidence)",
              decision,
              current,
              steps,
              decisions
            )
          case .wait, .done, .blocked:
            guard lowConfidenceFallbackWaits < Self.maximumLowConfidenceFallbackWaits else {
              return await result(
                .lowConfidence,
                "Non-mutating decisions remained below confidence \(configuration.minimumConfidence) after \(Self.maximumLowConfidenceFallbackWaits) fallback waits",
                decision,
                current,
                steps,
                decisions
              )
            }
            guard steps < configuration.maxSteps else {
              return await result(
                .stepLimit, "Step budget exhausted", decision, current, steps, decisions)
            }
            lowConfidenceFallbackWaits += 1
            try await trace.record(
              "fallback-wait-\(lowConfidenceFallbackWaits)",
              value:
                "Low-confidence \(decision.operation.rawValue) (\(decision.confidence)); waiting for fresh evidence"
            )
            try await clock.sleep(for: .seconds(1))
            let post = try await observe(configuration, index: decisions)
            steps += 1
            let screenChanged = post.fingerprint != current.fingerprint
            history.append(
              AgentHistoryEntry(
                operation: .wait,
                target: nil,
                textLength: nil,
                screenChanged: screenChanged
              )
            )
            current = post
            observation = post
            if screenChanged { lowConfidenceFallbackWaits = 0 }
            continue
          }
        }

        lowConfidenceFallbackWaits = 0

        switch decision.operation {
        case .blocked:
          return await result(
            .blocked, "Jev found no offered operation that can make progress", decision, current,
            steps, decisions)
        case .done:
          let fresh = try await observe(configuration, index: decisions)
          guard fresh.fingerprint == current.fingerprint else {
            current = fresh
            observation = fresh
            staleDecisions += 1
            if staleDecisions >= configuration.staleDecisionLimit {
              return await result(
                .unstableUI, "UI changed before completion could be accepted", decision, current,
                steps, decisions)
            }
            continue
          }
          if let verifier, try await verifier.verify(goal: configuration.goal, observation: fresh) {
            return await result(
              .verifiedSuccess, "Task-specific verifier confirmed success", decision, fresh, steps,
              decisions)
          }
          return await result(
            .modelDone,
            "Jev judged the stable UI complete; completion was not independently verified",
            decision,
            fresh,
            steps,
            decisions
          )
        case .wait:
          guard steps < configuration.maxSteps else {
            return await result(
              .stepLimit, "Step budget exhausted", decision, current, steps, decisions)
          }
          try await clock.sleep(for: .seconds(1))
          let post = try await observe(configuration, index: decisions)
          steps += 1
          history.append(
            AgentHistoryEntry(
              operation: .wait,
              target: nil,
              textLength: nil,
              screenChanged: post.fingerprint != current.fingerprint
            )
          )
          current = post
          observation = post
        case .tap, .typeText, .scrollUp, .scrollDown:
          guard steps < configuration.maxSteps else {
            return await result(
              .stepLimit, "Step budget exhausted", decision, current, steps, decisions)
          }
          if decision.operation == .typeText && decision.text == nil {
            return await result(
              .needsInput, "No exact supplied text candidate fits the focused field", decision,
              current, steps, decisions)
          }

          let fresh = try await observe(configuration, index: decisions)
          observation = fresh
          guard let prepared = try prepare(decision: decision, source: current, fresh: fresh) else {
            staleDecisions += 1
            current = fresh
            observation = fresh
            if staleDecisions >= configuration.staleDecisionLimit {
              return await result(
                .unstableUI, "Selected targets repeatedly became stale", decision, current, steps,
                decisions)
            }
            continue
          }
          staleDecisions = 0
          let signature = "\(fresh.fingerprint)|\(decision.operation.rawValue)|\(prepared.command)"
          if signature == lastActionSignature {
            repeatedNoOps += 1
            if repeatedNoOps >= configuration.repeatedNoOpLimit {
              return await result(
                .stuck, "The same action repeated against an unchanged UI", decision, fresh, steps,
                decisions)
            }
          } else {
            repeatedNoOps = 0
          }
          lastActionSignature = signature

          try await trace.record("action-\(steps + 1)", value: prepared.command)
          let actionStartedAt = clock.now()
          let post = try await device.execute(
            sessionKey: configuration.sessionKey,
            command: prepared.command,
            bundleIdentifier: configuration.bundleIdentifier
          )
          steps += 1
          try await trace.record(
            "action-\(steps)-timing",
            value: TraceTiming(
              milliseconds: elapsedMilliseconds(since: actionStartedAt), kind: "device_mutation")
          )
          try await recordObservation(post, name: "post-action-\(steps)")
          if decision.operation == .typeText {
            guard let text = decision.text,
              try await verifyText(
                text,
                identity: prepared.fieldIdentity,
                initialPost: post,
                configuration: configuration
              )
            else {
              return await result(
                .inputUnverified, "Typed value could not be read back exactly", decision, post,
                steps, decisions)
            }
          }
          history.append(
            AgentHistoryEntry(
              operation: decision.operation,
              target: prepared.targetLabel,
              textLength: decision.text?.count,
              screenChanged: post.fingerprint != fresh.fingerprint
            )
          )
          current = post
          observation = post
        }
      }
    } catch is CancellationError {
      return await result(.cancelled, "Run cancelled", nil, observation, steps, decisions)
    } catch AgentError.sessionExpired {
      return await result(
        .sessionExpired, AgentError.sessionExpired.description, nil, observation, steps, decisions)
    } catch AgentError.ambiguousMutation(let message) {
      return await result(.ambiguousMutation, message, nil, observation, steps, decisions)
    } catch AgentError.invalidPolicyResponse(let message) {
      return await result(.invalidPolicyResponse, message, nil, observation, steps, decisions)
    } catch {
      return await result(
        .observationFailure, String(describing: error), nil, observation, steps, decisions)
    }
  }

  private struct PreparedAction {
    let command: String
    let targetLabel: String?
    let fieldIdentity: SemanticIdentity?
  }

  private func prepare(
    decision: AgentDecision,
    source: DeviceObservation,
    fresh: DeviceObservation
  ) throws -> PreparedAction? {
    switch decision.operation {
    case .tap:
      guard let identity = decision.target,
        let target = TargetResolver.resolve(identity, in: fresh)
      else { return nil }
      return PreparedAction(
        command: try DeviceCommandBuilder.tap(target),
        targetLabel: target.label ?? target.identifier,
        fieldIdentity: nil
      )
    case .typeText:
      guard let text = decision.text, let original = source.focusedField,
        let field = TargetResolver.resolve(original.identity, in: fresh),
        field.isFocusedEditableField
      else { return nil }
      return PreparedAction(
        command: try DeviceCommandBuilder.typeText(text, field: field),
        targetLabel: field.label ?? field.identifier,
        fieldIdentity: field.identity
      )
    case .scrollUp, .scrollDown:
      let region: HierarchyElement?
      if let identity = decision.target {
        guard let resolved = TargetResolver.resolve(identity, in: fresh), resolved.isScrollRegion
        else {
          return nil
        }
        region = resolved
      } else {
        region = nil
      }
      return PreparedAction(
        command: try DeviceCommandBuilder.scroll(
          decision.operation, region: region, observation: fresh),
        targetLabel: region?.label ?? region?.role ?? "viewport",
        fieldIdentity: nil
      )
    default: return nil
    }
  }

  private func verifyText(
    _ text: String,
    identity: SemanticIdentity?,
    initialPost: DeviceObservation,
    configuration: AgentConfiguration
  ) async throws -> Bool {
    guard let identity else { return false }
    var observation = initialPost
    for attempt in 0...4 {
      if let field = TargetResolver.resolveFieldForReadback(identity, in: observation),
        field.value == text
      {
        return true
      }
      guard attempt < 4 else { break }
      try await clock.sleep(for: .milliseconds(500))
      observation = try await observe(configuration, index: 10_000 + attempt)
    }
    return false
  }

  private func observe(_ configuration: AgentConfiguration, index: Int) async throws
    -> DeviceObservation
  {
    let startedAt = clock.now()
    let observation = try await device.observe(
      sessionKey: configuration.sessionKey,
      bundleIdentifier: configuration.bundleIdentifier
    )
    try await recordObservation(observation, name: "observation-\(index)")
    try await trace.record(
      "observation-\(index)-timing",
      value: TraceTiming(
        milliseconds: elapsedMilliseconds(since: startedAt), kind: "device_snapshot")
    )
    return observation
  }

  private struct TraceTiming: Codable, Sendable {
    let milliseconds: Int
    let kind: String
  }

  private func elapsedMilliseconds(since start: Date) -> Int {
    max(0, Int(clock.now().timeIntervalSince(start) * 1_000))
  }

  private func recordObservation(_ observation: DeviceObservation, name: String) async throws {
    try await trace.record(name, value: observation)
    try await trace.copyArtifact(at: observation.artifacts.hierarchyPath, name: "\(name)-hierarchy")
    if let screenshot = observation.artifacts.screenshotPath {
      try await trace.copyArtifact(at: screenshot, name: "\(name)-screenshot")
    }
  }

  private func result(
    _ outcome: AgentTerminalOutcome,
    _ message: String,
    _ decision: AgentDecision?,
    _ observation: DeviceObservation?,
    _ steps: Int,
    _ decisions: Int
  ) async -> AgentRunResult {
    let result = AgentRunResult(
      outcome: outcome,
      message: message,
      decision: decision,
      finalObservation: observation,
      executedSteps: steps,
      decisions: decisions,
      traceDirectory: trace.directory
    )
    try? await trace.record("outcome", value: result)
    return result
  }
}
