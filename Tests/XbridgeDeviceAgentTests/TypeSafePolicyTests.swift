import Foundation
import Testing

@testable import XbridgeDeviceAgent

private actor QueueTransport: TypeSafeHTTPTransport {
  struct Item: Sendable {
    let status: Int
    let data: Data
  }

  private var items: [Item]
  private(set) var requests: [URLRequest] = []

  init(_ items: [Item]) { self.items = items }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    let item = items.removeFirst()
    let response = HTTPURLResponse(
      url: try #require(request.url),
      statusCode: item.status,
      httpVersion: nil,
      headerFields: nil
    )!
    return (item.data, response)
  }
}

@Suite struct TypeSafePolicyTests {
  private let operationKeys = [
    "TAP", "TYPE_TEXT", "SCROLL_UP", "SCROLL_DOWN", "WAIT", "DONE", "BLOCKED"
  ]
  private let tapKeys = ["tap_0", "tap_1", "tap_2", "tap_3", "tap_4"]

  @Test func validatesAndMapsConsumedAnswersWhileIgnoringUnusedHeads() async throws {
    let data = try responseData(
      operation: TestSupport.answer(choice: "TAP", keys: operationKeys, confidence: 0.8),
      tap: TestSupport.answer(choice: "tap_0", keys: tapKeys, confidence: 0.7),
      extraAnswers: [
        "text_value": ChoiceAnswer(
          type: "wrong",
          choice: "invented",
          probabilities: [:],
          confidence: 0
        )
      ]
    )
    let transport = QueueTransport([.init(status: 200, data: data)])
    let client = try TypeSafePolicyClient(apiKey: "secret", transport: transport)
    let decision = try await client.decide(
      observation: TestSupport.observation(),
      configuration: configuration(),
      history: []
    )

    #expect(decision.operation == .tap)
    #expect(decision.target?.identifier == "back")
    #expect(decision.confidence == 0.7)
    #expect(decision.metadata?.returnedModel == "jev-1.13.0")
    #expect(decision.metadata?.inputTokens == 100)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    #expect(
      !(String(decoding: try #require(requests[0].httpBody), as: UTF8.self).contains("secret")))
  }

  @Test(
    "rejects malformed consumed distributions",
    arguments: [
      ChoiceAnswer(type: "noul", choice: "tap_0", probabilities: ["tap_0": 1], confidence: 1),
      ChoiceAnswer(type: "choice", choice: "tap_0", probabilities: ["tap_0": 1], confidence: 1),
      ChoiceAnswer(
        type: "choice",
        choice: "tap_0",
        probabilities: ["tap_0": 0.2, "tap_1": 0.8, "tap_2": 0, "tap_3": 0],
        confidence: 0.5
      ),
      ChoiceAnswer(
        type: "choice",
        choice: "tap_0",
        probabilities: ["tap_0": 0.7, "tap_1": 0.1, "tap_2": 0.1, "tap_3": 0.2],
        confidence: 1.2
      ),
      ChoiceAnswer(
        type: "choice",
        choice: "tap_0",
        probabilities: ["tap_0": 0.7, "tap_1": 0.1, "tap_2": 0.1, "tap_3": 0.3],
        confidence: 0.5
      )
    ]
  )
  func rejectsMalformedDistributions(answer: ChoiceAnswer) async throws {
    let data = try responseData(
      operation: TestSupport.answer(choice: "TAP", keys: operationKeys),
      tap: answer
    )
    let client = try TypeSafePolicyClient(
      apiKey: "secret",
      transport: QueueTransport([.init(status: 200, data: data)])
    )
    await #expect(throws: AgentError.self) {
      try await client.decide(
        observation: TestSupport.observation(),
        configuration: configuration(),
        history: []
      )
    }
  }

  @Test func retriesOnlyTransientHTTPResponses() async throws {
    let valid = try responseData(
      operation: TestSupport.answer(choice: "DONE", keys: operationKeys),
      tap: nil
    )
    let transport = QueueTransport([
      .init(status: 429, data: Data()),
      .init(status: 200, data: valid)
    ])
    let client = try TypeSafePolicyClient(apiKey: "secret", transport: transport)
    let decision = try await client.decide(
      observation: TestSupport.observation(),
      configuration: configuration(),
      history: []
    )
    #expect(decision.operation == .done)
    #expect(decision.metadata?.attempts == 2)
    #expect(await transport.requests.count == 2)
  }

  @Test func doesNotRetryNonRetryableHTTPResponse() async throws {
    let transport = QueueTransport([.init(status: 401, data: Data("unauthorized".utf8))])
    let client = try TypeSafePolicyClient(apiKey: "secret", transport: transport)
    await #expect(throws: AgentError.self) {
      try await client.decide(
        observation: TestSupport.observation(),
        configuration: configuration(),
        history: []
      )
    }
    #expect(await transport.requests.count == 1)
  }

  private func configuration() throws -> AgentConfiguration {
    try AgentConfiguration(
      sessionKey: "Test",
      goal: "Tap Back and enter Kai",
      textCandidates: ["Kai"]
    )
  }

  private func responseData(
    operation: ChoiceAnswer,
    tap: ChoiceAnswer?,
    extraAnswers: [String: ChoiceAnswer] = [:]
  ) throws -> Data {
    var answers = extraAnswers
    answers["operation"] = operation
    if let tap { answers["tap_target"] = tap }
    struct Response: Encodable {
      let model: String
      let answers: [String: ChoiceAnswer]
      let usage: [String: Int]
    }
    return try JSONEncoder().encode(
      Response(
        model: "jev-1.13.0",
        answers: answers,
        usage: ["input_tokens": 100, "output_tokens": 20]
      )
    )
  }
}
