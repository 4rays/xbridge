import Foundation
import XbridgeCore

public protocol TypeSafeHTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTypeSafeTransport: TypeSafeHTTPTransport {
  private let session: URLSession

  public init(session: URLSession = .shared) { self.session = session }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw AgentError.policyTransport("TypeSafe returned a non-HTTP response")
    }
    return (data, http)
  }
}

private struct SystemOneResponse: Codable {
  struct Usage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
      case inputTokens = "input_tokens"
      case outputTokens = "output_tokens"
    }
  }

  let model: String
  let answers: [String: ChoiceAnswer]
  let usage: Usage?
}

public struct TypeSafePolicyClient<Transport: TypeSafeHTTPTransport>: AgentPolicyEvaluating {
  public static var endpoint: URL { URL(string: "https://api.typesafe.ai/v1/systemone")! }

  private let apiKey: String
  private let model: String
  private let transport: Transport
  private let timeout: TimeInterval

  public init(
    apiKey: String,
    model: String = "jev-latest",
    transport: Transport,
    timeout: TimeInterval = 30
  ) throws {
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentError.invalidConfiguration("TYPESAFE_API_KEY is required for device-agent")
    }
    self.apiKey = apiKey
    self.model = model
    self.transport = transport
    self.timeout = timeout
  }

  public func decide(
    observation: DeviceObservation,
    configuration: AgentConfiguration,
    history: [AgentHistoryEntry]
  ) async throws -> AgentDecision {
    let plan = try StateProjection.build(
      observation: observation,
      configuration: configuration,
      history: history,
      model: model
    )
    let body = try JSONEncoder().encode(plan.request)
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let started = ContinuousClock.now
    var attempts = 0
    let response: SystemOneResponse
    let responseData: Data
    while true {
      attempts += 1
      do {
        let (data, http) = try await transport.data(for: request)
        if [429, 529].contains(http.statusCode), attempts <= configuration.readOnlyRetries + 1 {
          try await Task.sleep(for: .milliseconds(150 * attempts))
          continue
        }
        guard (200..<300).contains(http.statusCode) else {
          let detail = String(data: data, encoding: .utf8) ?? ""
          throw AgentError.policyTransport(
            "TypeSafe HTTP \(http.statusCode)\(detail.isEmpty ? "" : ": \(detail)")"
          )
        }
        response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        responseData = data
        break
      } catch let error as AgentError {
        throw error
      } catch {
        guard attempts <= configuration.readOnlyRetries else {
          throw AgentError.policyTransport("TypeSafe request failed: \(error.localizedDescription)")
        }
        try await Task.sleep(for: .milliseconds(150 * attempts))
      }
    }

    let latency = started.duration(to: .now)
    let milliseconds =
      Int(latency.components.seconds * 1_000)
      + Int(latency.components.attoseconds / 1_000_000_000_000_000)
    let metadata = PolicyMetadata(
      requestedModel: model,
      returnedModel: response.model,
      inputTokens: response.usage?.inputTokens,
      outputTokens: response.usage?.outputTokens,
      latencyMilliseconds: milliseconds,
      requestBytes: body.count,
      droppedVisibleText: plan.droppedVisibleText,
      droppedTargets: plan.droppedTargets,
      attempts: attempts,
      request: try JSONDecoder().decode(JSONValue.self, from: body),
      response: try JSONDecoder().decode(JSONValue.self, from: responseData)
    )
    return try map(response: response, plan: plan, metadata: metadata)
  }

  private func map(
    response: SystemOneResponse,
    plan: RequestPlan,
    metadata: PolicyMetadata
  ) throws -> AgentDecision {
    guard let operationAnswer = response.answers["operation"] else {
      throw AgentError.invalidPolicyResponse("Missing operation answer")
    }
    guard let operationQuestion = plan.request.questions["operation"] else {
      throw AgentError.invalidPolicyResponse("Missing operation question")
    }
    try validate(operationAnswer, criteria: Set(operationQuestion.criteria.keys))
    guard let operation = AgentOperation(rawValue: operationAnswer.choice) else {
      throw AgentError.invalidPolicyResponse("Unknown operation: \(operationAnswer.choice)")
    }

    switch operation {
    case .tap:
      let targetAnswer = try consumedAnswer("tap_target", response: response, plan: plan)
      guard let target = plan.tapTargets[targetAnswer.choice] else {
        throw AgentError.invalidPolicyResponse("Unknown tap target: \(targetAnswer.choice)")
      }
      return AgentDecision(
        operation: operation,
        operationAnswer: operationAnswer,
        targetAnswer: targetAnswer,
        target: target,
        confidence: min(operationAnswer.confidence, targetAnswer.confidence),
        metadata: metadata
      )
    case .typeText:
      let targetAnswer = try consumedAnswer("text_value", response: response, plan: plan)
      guard plan.textValues.keys.contains(targetAnswer.choice) else {
        throw AgentError.invalidPolicyResponse("Unknown text candidate: \(targetAnswer.choice)")
      }
      return AgentDecision(
        operation: operation,
        operationAnswer: operationAnswer,
        targetAnswer: targetAnswer,
        target: nil,
        text: plan.textValues[targetAnswer.choice] ?? nil,
        confidence: min(operationAnswer.confidence, targetAnswer.confidence),
        metadata: metadata
      )
    case .scrollUp, .scrollDown:
      let targetAnswer = try consumedAnswer("scroll_target", response: response, plan: plan)
      guard plan.scrollTargets.keys.contains(targetAnswer.choice) else {
        throw AgentError.invalidPolicyResponse("Unknown scroll target: \(targetAnswer.choice)")
      }
      return AgentDecision(
        operation: operation,
        operationAnswer: operationAnswer,
        targetAnswer: targetAnswer,
        target: plan.scrollTargets[targetAnswer.choice] ?? nil,
        confidence: min(operationAnswer.confidence, targetAnswer.confidence),
        metadata: metadata
      )
    case .wait, .done, .blocked:
      return AgentDecision(
        operation: operation,
        operationAnswer: operationAnswer,
        confidence: operationAnswer.confidence,
        metadata: metadata
      )
    }
  }

  private func consumedAnswer(
    _ key: String,
    response: SystemOneResponse,
    plan: RequestPlan
  ) throws -> ChoiceAnswer {
    guard let answer = response.answers[key], let question = plan.request.questions[key] else {
      throw AgentError.invalidPolicyResponse("Missing consumed answer: \(key)")
    }
    try validate(answer, criteria: Set(question.criteria.keys))
    return answer
  }

  private func validate(_ answer: ChoiceAnswer, criteria: Set<String>) throws {
    guard answer.type == "choice" else {
      throw AgentError.invalidPolicyResponse("Consumed answer type must be choice")
    }
    guard criteria.contains(answer.choice), Set(answer.probabilities.keys) == criteria else {
      throw AgentError.invalidPolicyResponse("Choice keys do not exactly match offered criteria")
    }
    guard answer.confidence.isFinite && (0...1).contains(answer.confidence) else {
      throw AgentError.invalidPolicyResponse("Choice confidence is outside 0...1")
    }
    guard answer.probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      throw AgentError.invalidPolicyResponse("Choice probabilities must be finite values in 0...1")
    }
    let sum = answer.probabilities.values.reduce(0, +)
    // The service currently serializes probabilities to two decimal places, so a
    // sparse distribution can legitimately total 0.99 or 1.01 after rounding.
    guard abs(sum - 1) <= 0.02 else {
      throw AgentError.invalidPolicyResponse("Choice probabilities must sum to one")
    }
    guard let selected = answer.probabilities[answer.choice],
      selected == answer.probabilities.values.max()
    else {
      throw AgentError.invalidPolicyResponse("Selected choice is not an argmax")
    }
  }
}

extension TypeSafePolicyClient where Transport == URLSessionTypeSafeTransport {
  public init(apiKey: String, model: String = "jev-latest", timeout: TimeInterval = 30) throws {
    try self.init(
      apiKey: apiKey,
      model: model,
      transport: URLSessionTypeSafeTransport(),
      timeout: timeout
    )
  }
}
