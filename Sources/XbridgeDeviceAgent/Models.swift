import Foundation
import XbridgeCore

public struct AgentPoint: Codable, Hashable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct AgentRect: Codable, Hashable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var center: AgentPoint {
    AgentPoint(x: x + width / 2, y: y + height / 2)
  }
}

public enum ElementProvenance: String, Codable, Sendable {
  case accessibilityHierarchy
}

public struct SemanticIdentity: Codable, Hashable, Sendable {
  public let path: String
  public let identifier: String?
  public let role: String
  public let label: String?
  public let value: String?
  public let parentRole: String?

  public init(
    path: String,
    identifier: String?,
    role: String,
    label: String?,
    value: String?,
    parentRole: String?
  ) {
    self.path = path
    self.identifier = identifier
    self.role = role
    self.label = label
    self.value = value
    self.parentRole = parentRole
  }
}

public struct HierarchyElement: Codable, Hashable, Sendable {
  public let path: String
  public let depth: Int
  public let role: String
  public let identifier: String?
  public let label: String?
  public let value: String?
  public let frame: AgentRect?
  public let hitPoint: AgentPoint?
  public let enabled: Bool?
  public let selected: Bool?
  public let focused: Bool?
  public let secure: Bool?
  public let editable: Bool?
  public let hidden: Bool?
  public let traits: [String]
  public let rawSource: String
  public let provenance: ElementProvenance
  public let parentRole: String?

  public init(
    path: String,
    depth: Int,
    role: String,
    identifier: String? = nil,
    label: String? = nil,
    value: String? = nil,
    frame: AgentRect? = nil,
    hitPoint: AgentPoint? = nil,
    enabled: Bool? = nil,
    selected: Bool? = nil,
    focused: Bool? = nil,
    secure: Bool? = nil,
    editable: Bool? = nil,
    hidden: Bool? = nil,
    traits: [String] = [],
    rawSource: String,
    provenance: ElementProvenance = .accessibilityHierarchy,
    parentRole: String? = nil
  ) {
    self.path = path
    self.depth = depth
    self.role = role
    self.identifier = identifier
    self.label = label
    self.value = value
    self.frame = frame
    self.hitPoint = hitPoint
    self.enabled = enabled
    self.selected = selected
    self.focused = focused
    self.secure = secure
    self.editable = editable
    self.hidden = hidden
    self.traits = traits
    self.rawSource = rawSource
    self.provenance = provenance
    self.parentRole = parentRole
  }

  public var identity: SemanticIdentity {
    SemanticIdentity(
      path: path,
      identifier: identifier,
      role: role,
      label: label,
      value: value,
      parentRole: parentRole
    )
  }

  public var isVisible: Bool {
    hidden != true && (frame?.width ?? 1) > 0 && (frame?.height ?? 1) > 0
  }

  public var isActionable: Bool {
    Self.interactiveRoles.contains(role) && enabled != false && secure != true && isVisible
      && (hitPoint != nil || frame != nil)
  }

  public var isScrollRegion: Bool {
    Self.scrollRoles.contains(role) && enabled != false && isVisible
      && (hitPoint != nil || frame != nil)
  }

  public var isFocusedEditableField: Bool {
    focused == true && editable == true && secure != true && enabled != false
  }

  private static let interactiveRoles: Set<String> = [
    "Button", "Cell", "Link", "MenuItem", "SearchField", "SecureTextField",
    "SegmentedControl", "Slider", "Switch", "Tab", "TextField", "TextView"
  ]

  private static let scrollRoles: Set<String> = ["CollectionView", "ScrollView", "Table"]
}

public struct DeviceHubArtifacts: Codable, Hashable, Sendable {
  public let hierarchyPath: String
  public let screenshotPath: String?
  public let logsPath: String?

  public init(hierarchyPath: String, screenshotPath: String?, logsPath: String?) {
    self.hierarchyPath = hierarchyPath
    self.screenshotPath = screenshotPath
    self.logsPath = logsPath
  }
}

public struct DeviceObservation: Codable, Sendable {
  public let applicationState: String
  public let bundleIdentifier: String?
  public let capturedAt: Date
  public let artifacts: DeviceHubArtifacts
  public let hierarchy: String
  public let elements: [HierarchyElement]
  public let fingerprint: String

  public init(
    applicationState: String,
    bundleIdentifier: String?,
    capturedAt: Date,
    artifacts: DeviceHubArtifacts,
    hierarchy: String,
    elements: [HierarchyElement],
    fingerprint: String
  ) {
    self.applicationState = applicationState
    self.bundleIdentifier = bundleIdentifier
    self.capturedAt = capturedAt
    self.artifacts = artifacts
    self.hierarchy = hierarchy
    self.elements = elements
    self.fingerprint = fingerprint
  }

  public var actionableElements: [HierarchyElement] { elements.filter(\.isActionable) }
  public var scrollRegions: [HierarchyElement] { elements.filter(\.isScrollRegion) }
  public var focusedField: HierarchyElement? { elements.first(where: \.isFocusedEditableField) }
}

public enum AgentOperation: String, Codable, CaseIterable, Sendable {
  case tap = "TAP"
  case typeText = "TYPE_TEXT"
  case scrollUp = "SCROLL_UP"
  case scrollDown = "SCROLL_DOWN"
  case wait = "WAIT"
  case done = "DONE"
  case blocked = "BLOCKED"
}

public struct ChoiceAnswer: Codable, Sendable {
  public let type: String
  public let choice: String
  public let probabilities: [String: Double]
  public let confidence: Double

  public init(type: String, choice: String, probabilities: [String: Double], confidence: Double) {
    self.type = type
    self.choice = choice
    self.probabilities = probabilities
    self.confidence = confidence
  }
}

public struct AgentDecision: Codable, Sendable {
  public let operation: AgentOperation
  public let operationAnswer: ChoiceAnswer
  public let targetAnswer: ChoiceAnswer?
  public let target: SemanticIdentity?
  public let text: String?
  public let confidence: Double
  public let metadata: PolicyMetadata?

  public init(
    operation: AgentOperation,
    operationAnswer: ChoiceAnswer,
    targetAnswer: ChoiceAnswer? = nil,
    target: SemanticIdentity? = nil,
    text: String? = nil,
    confidence: Double,
    metadata: PolicyMetadata? = nil
  ) {
    self.operation = operation
    self.operationAnswer = operationAnswer
    self.targetAnswer = targetAnswer
    self.target = target
    self.text = text
    self.confidence = confidence
    self.metadata = metadata
  }
}

public struct PolicyMetadata: Codable, Sendable {
  public let requestedModel: String
  public let returnedModel: String
  public let inputTokens: Int?
  public let outputTokens: Int?
  public let latencyMilliseconds: Int
  public let requestBytes: Int
  public let droppedVisibleText: Int
  public let droppedTargets: Int
  public let attempts: Int
  public let request: JSONValue
  public let response: JSONValue

  public init(
    requestedModel: String,
    returnedModel: String,
    inputTokens: Int?,
    outputTokens: Int?,
    latencyMilliseconds: Int,
    requestBytes: Int,
    droppedVisibleText: Int,
    droppedTargets: Int,
    attempts: Int,
    request: JSONValue,
    response: JSONValue
  ) {
    self.requestedModel = requestedModel
    self.returnedModel = returnedModel
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.latencyMilliseconds = latencyMilliseconds
    self.requestBytes = requestBytes
    self.droppedVisibleText = droppedVisibleText
    self.droppedTargets = droppedTargets
    self.attempts = attempts
    self.request = request
    self.response = response
  }
}

public struct AgentHistoryEntry: Codable, Sendable {
  public let operation: AgentOperation
  public let target: String?
  public let textLength: Int?
  public let screenChanged: Bool

  public init(operation: AgentOperation, target: String?, textLength: Int?, screenChanged: Bool) {
    self.operation = operation
    self.target = target
    self.textLength = textLength
    self.screenChanged = screenChanged
  }
}

public enum AgentTerminalOutcome: String, Codable, Sendable {
  case preview
  case modelDone = "model_done"
  case verifiedSuccess = "verified_success"
  case blocked
  case needsInput = "needs_input"
  case lowConfidence = "low_confidence"
  case stuck
  case unstableUI = "unstable_ui"
  case inputUnverified = "input_unverified"
  case sessionExpired = "session_expired"
  case ambiguousMutation = "ambiguous_mutation"
  case stepLimit = "step_limit"
  case decisionLimit = "decision_limit"
  case observationFailure = "observation_failure"
  case invalidPolicyResponse = "invalid_policy_response"
  case cancelled
}

public struct AgentRunResult: Codable, Sendable {
  public let outcome: AgentTerminalOutcome
  public let message: String
  public let decision: AgentDecision?
  public let finalObservation: DeviceObservation?
  public let executedSteps: Int
  public let decisions: Int
  public let traceDirectory: String?

  public init(
    outcome: AgentTerminalOutcome,
    message: String,
    decision: AgentDecision?,
    finalObservation: DeviceObservation?,
    executedSteps: Int,
    decisions: Int,
    traceDirectory: String?
  ) {
    self.outcome = outcome
    self.message = message
    self.decision = decision
    self.finalObservation = finalObservation
    self.executedSteps = executedSteps
    self.decisions = decisions
    self.traceDirectory = traceDirectory
  }
}

public enum AgentError: Error, CustomStringConvertible, Sendable {
  case invalidConfiguration(String)
  case observation(String)
  case invalidPolicyResponse(String)
  case policyTransport(String)
  case sessionExpired
  case ambiguousMutation(String)
  case staleTarget
  case unsupportedText
  case trace(String)

  public var description: String {
    switch self {
    case .invalidConfiguration(let message), .observation(let message),
      .invalidPolicyResponse(let message), .policyTransport(let message),
      .ambiguousMutation(let message), .trace(let message):
      return message
    case .sessionExpired: return "Device Hub session expired"
    case .staleTarget: return "The selected target is no longer uniquely available"
    case .unsupportedText: return "Text contains unsupported control characters"
    }
  }
}

public struct AgentConfiguration: Codable, Sendable {
  public let sessionKey: String
  public let goal: String
  public let act: Bool
  public let bundleIdentifier: String?
  public let maxSteps: Int
  public let maxDecisions: Int
  public let minimumConfidence: Double
  public let textCandidates: [String]
  public let readOnlyRetries: Int
  public let staleDecisionLimit: Int
  public let repeatedNoOpLimit: Int
  public let traceDirectory: String?

  public init(
    sessionKey: String,
    goal: String,
    act: Bool = false,
    bundleIdentifier: String? = nil,
    maxSteps: Int = 12,
    maxDecisions: Int? = nil,
    minimumConfidence: Double = 0.5,
    textCandidates: [String] = [],
    readOnlyRetries: Int = 2,
    staleDecisionLimit: Int = 3,
    repeatedNoOpLimit: Int = 2,
    traceDirectory: String? = nil
  ) throws {
    let key = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      throw AgentError.invalidConfiguration("Session key must not be empty")
    }
    guard !trimmedGoal.isEmpty else {
      throw AgentError.invalidConfiguration("Goal must not be empty")
    }
    guard maxSteps > 0 else {
      throw AgentError.invalidConfiguration("--steps must be greater than zero")
    }
    let decisionBudget = maxDecisions ?? max(maxSteps * 3, maxSteps + 2)
    guard decisionBudget > 0 else {
      throw AgentError.invalidConfiguration("Decision budget must be greater than zero")
    }
    guard minimumConfidence.isFinite && (0...1).contains(minimumConfidence) else {
      throw AgentError.invalidConfiguration("--min-confidence must be between 0 and 1")
    }
    guard readOnlyRetries >= 0 && staleDecisionLimit > 0 && repeatedNoOpLimit > 0 else {
      throw AgentError.invalidConfiguration("Retry and repetition limits must be nonnegative")
    }
    for text in textCandidates where !TextCandidates.isSupported(text) {
      throw AgentError.unsupportedText
    }

    self.sessionKey = key
    self.goal = trimmedGoal
    self.act = act
    self.bundleIdentifier = bundleIdentifier
    self.maxSteps = maxSteps
    self.maxDecisions = decisionBudget
    self.minimumConfidence = minimumConfidence
    self.textCandidates = textCandidates
    self.readOnlyRetries = readOnlyRetries
    self.staleDecisionLimit = staleDecisionLimit
    self.repeatedNoOpLimit = repeatedNoOpLimit
    self.traceDirectory = traceDirectory
  }
}

public protocol DeviceHubControlling: Sendable {
  func observe(sessionKey: String, bundleIdentifier: String?) async throws -> DeviceObservation
  func execute(
    sessionKey: String,
    command: String,
    bundleIdentifier: String?
  ) async throws -> DeviceObservation
}

public protocol AgentPolicyEvaluating: Sendable {
  func decide(
    observation: DeviceObservation,
    configuration: AgentConfiguration,
    history: [AgentHistoryEntry]
  ) async throws -> AgentDecision
}

public protocol AgentTracing: Sendable {
  var directory: String? { get }
  func record<Value: Encodable & Sendable>(_ name: String, value: Value) async throws
  func copyArtifact(at path: String, name: String) async throws
}

public protocol AgentClock: Sendable {
  func now() -> Date
  func sleep(for duration: Duration) async throws
}

public protocol AgentOutcomeVerifying: Sendable {
  func verify(goal: String, observation: DeviceObservation) async throws -> Bool
}

public struct ContinuousAgentClock: AgentClock {
  public init() {}
  public func now() -> Date { Date() }
  public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}
