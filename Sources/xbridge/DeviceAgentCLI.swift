import Foundation
import XbridgeCore
import XbridgeDeviceAgent

enum DeviceAgentConsole {
  static func write(_ line: String) {
    guard let data = "\(line)\n".data(using: .utf8) else { return }
    try? FileHandle.standardError.write(contentsOf: data)
  }
}

struct CLIDeviceHubAdapter: DeviceHubControlling {
  let client: DaemonClient
  let readOnlyRetries: Int

  func observe(sessionKey: String, bundleIdentifier: String?) async throws -> DeviceObservation {
    var attempts = 0
    while true {
      attempts += 1
      DeviceAgentConsole.write("[device] snapshot attempt \(attempts)")
      do {
        return try snapshot(sessionKey: sessionKey, bundleIdentifier: bundleIdentifier)
      } catch AgentError.sessionExpired {
        throw AgentError.sessionExpired
      } catch {
        guard attempts <= readOnlyRetries else { throw error }
        DeviceAgentConsole.write(
          "[device] snapshot failed: \(error.localizedDescription); retrying")
        try await Task.sleep(for: .milliseconds(100 * attempts))
      }
    }
  }

  func execute(
    sessionKey: String,
    command: String,
    bundleIdentifier: String?
  ) async throws -> DeviceObservation {
    let request = makeRequest(
      sessionKey: sessionKey,
      command: command,
      bundleIdentifier: bundleIdentifier
    )
    DeviceAgentConsole.write("[device] dispatching mutation (never automatically retried)")
    let response: LocalRPCResponse
    do {
      response = try client.send(request)
    } catch {
      throw AgentError.ambiguousMutation(
        "Device Hub transport failed after dispatch; the interaction was not retried: \(error.localizedDescription)"
      )
    }
    guard response.ok, let result = response.result else {
      let message = response.error?.message ?? "Unknown Device Hub mutation failure"
      if Self.isSessionExpired(message) { throw AgentError.sessionExpired }
      throw AgentError.ambiguousMutation(
        "Device Hub did not confirm whether the interaction executed; it was not retried: \(message)"
      )
    }
    return try makeObservation(from: result)
  }

  private func snapshot(sessionKey: String, bundleIdentifier: String?) throws -> DeviceObservation {
    let response = try client.send(
      makeRequest(sessionKey: sessionKey, command: nil, bundleIdentifier: bundleIdentifier)
    )
    guard response.ok, let result = response.result else {
      let message = response.error?.message ?? "Unknown Device Hub snapshot failure"
      if Self.isSessionExpired(message) { throw AgentError.sessionExpired }
      throw AgentError.observation(message)
    }
    return try makeObservation(from: result)
  }

  private func makeObservation(from value: JSONValue) throws -> DeviceObservation {
    let decoded = try DeviceHubResultDecoder.decode(value)
    let hierarchy: String
    do {
      hierarchy = try String(contentsOfFile: decoded.hierarchyPath, encoding: .utf8)
    } catch {
      throw AgentError.observation(
        "Cannot read Device Hub hierarchy at \(decoded.hierarchyPath): \(error.localizedDescription)"
      )
    }
    return try ObservationFactory.make(decoded: decoded, hierarchy: hierarchy)
  }

  private func makeRequest(
    sessionKey: String,
    command: String?,
    bundleIdentifier: String?
  ) -> LocalRPCRequest {
    var arguments: [String: JSONValue] = ["interactSessionKey": .string(sessionKey)]
    if let command { arguments["interactionCommand"] = .string(command) }
    if let bundleIdentifier { arguments["activationBundleId"] = .string(bundleIdentifier) }
    let parameters = CallToolParams(
      tool: XcodeTool.deviceInteractionSynthesize,
      arguments: .object(arguments)
    )
    let data = (try? JSONEncoder().encode(parameters)) ?? Data()
    let json = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
    return LocalRPCRequest(method: LocalRPCMethod.callTool, params: json)
  }

  private static func isSessionExpired(_ message: String) -> Bool {
    let lower = message.lowercased()
    return lower.contains("session not found") || lower.contains("session doesn't exist")
      || lower.contains("session does not exist")
  }
}

actor CLIProgressTraceWriter: AgentTracing {
  nonisolated var directory: String? { trace.directory }

  private let trace: LocalTraceWriter
  private var latestDecision: AgentDecision?

  init(trace: LocalTraceWriter) {
    self.trace = trace
  }

  func record<Value: Encodable & Sendable>(_ name: String, value: Value) async throws {
    try await trace.record(name, value: value)

    if let observation = value as? DeviceObservation {
      DeviceAgentConsole.write(
        DeviceAgentProgressFormatter.observation(name: name, observation: observation))
    } else if let decision = value as? AgentDecision {
      latestDecision = decision
      DeviceAgentConsole.write(
        DeviceAgentProgressFormatter.decision(name: name, decision: decision))
    } else if value is String, name.hasPrefix("action-"), !name.hasSuffix("-timing"),
      let latestDecision
    {
      DeviceAgentConsole.write(
        DeviceAgentProgressFormatter.action(name: name, decision: latestDecision))
    } else if let message = value as? String, name.hasPrefix("fallback-wait-") {
      DeviceAgentConsole.write(
        DeviceAgentProgressFormatter.fallbackWait(name: name, message: message))
    }
  }

  func copyArtifact(at path: String, name: String) async throws {
    try await trace.copyArtifact(at: path, name: name)
  }
}

enum DeviceAgentProgressFormatter {
  static func observation(name: String, observation: DeviceObservation) -> String {
    let focused = observation.focusedField?.label ?? observation.focusedField?.role ?? "none"
    return "[\(displayName(name))] app=\(observation.bundleIdentifier ?? "unknown") "
      + "actionable=\(observation.actionableElements.count) "
      + "scroll_regions=\(observation.scrollRegions.count) focused=\(quoted(focused)) "
      + "fingerprint=\(observation.fingerprint.prefix(10))"
  }

  static func decision(name: String, decision: AgentDecision) -> String {
    var details = "[\(displayName(name))] \(decision.operation.rawValue)"
    if let target = decision.target {
      details += " target=\(quoted(target.label ?? target.identifier ?? target.role))"
    }
    if decision.operation == .typeText {
      details += " text_length=\(decision.text?.count ?? 0)"
    }
    details += " confidence=\(String(format: "%.3f", decision.confidence))"
    if let metadata = decision.metadata {
      details += " latency=\(metadata.latencyMilliseconds)ms request=\(metadata.requestBytes)B"
    }
    return details
  }

  static func action(name: String, decision: AgentDecision) -> String {
    var details = "[\(displayName(name))] execute \(decision.operation.rawValue)"
    if let target = decision.target {
      details += " target=\(quoted(target.label ?? target.identifier ?? target.role))"
    }
    if decision.operation == .typeText {
      details += " text_length=\(decision.text?.count ?? 0)"
    }
    return details
  }

  static func fallbackWait(name: String, message: String) -> String {
    "[\(name.replacingOccurrences(of: "fallback-wait-", with: "fallback wait "))] \(message)"
  }

  private static func displayName(_ name: String) -> String {
    if name.hasPrefix("observation-") {
      return name.replacingOccurrences(of: "observation-", with: "observe ")
    }
    if name.hasPrefix("post-action-") {
      return name.replacingOccurrences(of: "post-action-", with: "observe post-act ")
    }
    if name.hasPrefix("decision-") {
      return name.replacingOccurrences(of: "decision-", with: "jev ")
    }
    if name.hasPrefix("action-") { return name.replacingOccurrences(of: "action-", with: "act ") }
    return name
  }

  private static func quoted(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\n", with: " ").prefix(80))\""
  }
}

enum DeviceAgentCLI {
  static let usage = """
    Usage: xbridge device-agent <session-key> <goal> [options]

      --act                    Execute actions (default is one-decision preview)
      --bundle-id <id>         Activate or constrain the target application
      --steps <n>              Maximum executed actions (default: 12)
      --min-confidence <p>     Minimum consumed confidence from 0...1 (default: 0.5)
      --text <value>           Add an exact text candidate; repeat as needed
      --trace <directory>      Write the owner-only run trace to this directory
    """

  static func run(arguments: [String], xcodePath: String?) async throws -> Int32 {
    if arguments.contains("--help") || arguments.contains("-h") {
      print(usage)
      return 0
    }
    let options = try DeviceAgentCommandOptions(arguments: arguments)
    let environment = ProcessInfo.processInfo.environment
    guard let apiKey = environment["TYPESAFE_API_KEY"], !apiKey.isEmpty else {
      throw AgentError.invalidConfiguration(
        "TYPESAFE_API_KEY is not set. Export it before using device-agent."
      )
    }
    let policy = try TypeSafePolicyClient(
      apiKey: apiKey,
      model: environment["TYPESAFE_MODEL"] ?? "jev-latest"
    )
    let localTrace = try LocalTraceWriter(directory: options.configuration.traceDirectory)
    let trace = CLIProgressTraceWriter(trace: localTrace)
    let device = CLIDeviceHubAdapter(
      client: DaemonClient(xcodePath: xcodePath, ioTimeoutSeconds: 20),
      readOnlyRetries: options.configuration.readOnlyRetries
    )
    DeviceAgentConsole.write("device-agent: \(options.configuration.act ? "act" : "preview")")
    DeviceAgentConsole.write("goal: \(options.configuration.goal)")
    if let directory = trace.directory { DeviceAgentConsole.write("trace: \(directory)") }
    let runner = DeviceAgentRunner(device: device, policy: policy, trace: trace)
    let result = await runner.run(configuration: options.configuration)

    print("status: \(result.outcome.rawValue)")
    print(result.message)
    if let decision = result.decision {
      print("operation: \(decision.operation.rawValue)")
      print(String(format: "confidence: %.3f", decision.confidence))
      let probabilities = decision.operationAnswer.probabilities
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\(String(format: "%.3f", $0.value))" }
        .joined(separator: ", ")
      print("probabilities: \(probabilities)")
    }
    if let observation = result.finalObservation {
      print("hierarchy: \(observation.artifacts.hierarchyPath)")
      if let screenshot = observation.artifacts.screenshotPath {
        print("screenshot: \(screenshot)")
      }
    }
    if let traceDirectory = result.traceDirectory { print("trace: \(traceDirectory)") }

    switch result.outcome {
    case .preview, .modelDone, .verifiedSuccess: return 0
    case .blocked, .needsInput, .lowConfidence, .stuck, .unstableUI, .inputUnverified,
      .stepLimit, .decisionLimit:
      return 2
    case .sessionExpired, .ambiguousMutation, .observationFailure, .invalidPolicyResponse,
      .cancelled:
      return 1
    }
  }
}
