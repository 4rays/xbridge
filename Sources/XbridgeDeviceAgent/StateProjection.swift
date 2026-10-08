import Foundation
import XbridgeCore

public enum AgentLimits {
  public static let maximumChoiceOptions = 250
  public static let maximumEncodedRequestBytes = 96 * 1024
  public static let maximumVisibleTextEntries = 300
  public static let maximumHistoryEntries = 8
}

public enum TextCandidates {
  public static func extract(goal: String, explicit: [String]) throws -> [String] {
    var result: [String] = []
    var seen: Set<String> = []

    func append(_ candidate: String) throws {
      guard isSupported(candidate) else { throw AgentError.unsupportedText }
      guard !candidate.isEmpty, seen.insert(candidate).inserted else { return }
      result.append(candidate)
    }

    for value in explicit { try append(value) }

    let words = goal.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return result }
    for length in stride(from: min(8, words.count), through: 1, by: -1) {
      for start in 0...(words.count - length) {
        try append(words[start..<(start + length)].joined(separator: " "))
      }
    }
    return result
  }

  public static func isSupported(_ value: String) -> Bool {
    !value.unicodeScalars.contains { scalar in
      CharacterSet.controlCharacters.contains(scalar) && scalar != "\n" && scalar != "\t"
    }
  }
}

struct ChoiceQuestion: Codable, Sendable {
  let type: String
  let instructions: String
  let criteria: [String: String?]

  init(instructions: String, criteria: [String: String?]) {
    self.type = "choice"
    self.instructions = instructions
    self.criteria = criteria
  }
}

struct SystemOneRequest: Codable, Sendable {
  let state: JSONValue
  let model: String
  let questions: [String: ChoiceQuestion]
}

struct RequestPlan: Sendable {
  let request: SystemOneRequest
  let tapTargets: [String: SemanticIdentity]
  let scrollTargets: [String: SemanticIdentity?]
  let textValues: [String: String?]
  let droppedVisibleText: Int
  let droppedTargets: Int
}

enum StateProjection {
  static func build(
    observation: DeviceObservation,
    configuration: AgentConfiguration,
    history: [AgentHistoryEntry],
    model: String
  ) throws -> RequestPlan {
    let actionable = Array(observation.actionableElements.prefix(AgentLimits.maximumChoiceOptions))
    let droppedTargets = max(0, observation.actionableElements.count - actionable.count)
    let textCandidates = try TextCandidates.extract(
      goal: configuration.goal,
      explicit: configuration.textCandidates
    )
    var visibleText = observation.elements.compactMap { element -> String? in
      guard element.isVisible, let label = element.label, !label.isEmpty else { return nil }
      if element.secure == true { return nil }
      return label
    }
    var seen: Set<String> = []
    visibleText = visibleText.filter { seen.insert($0).inserted }
    var droppedVisibleText = max(0, visibleText.count - AgentLimits.maximumVisibleTextEntries)
    visibleText = Array(visibleText.prefix(AgentLimits.maximumVisibleTextEntries))

    let tapTargets = Dictionary(
      uniqueKeysWithValues: actionable.enumerated().map { index, element in
        ("tap_\(index)", element.identity)
      })
    let scrollElements = Array(observation.scrollRegions.prefix(AgentLimits.maximumChoiceOptions))
    let scrollTargets: [String: SemanticIdentity?]
    if scrollElements.isEmpty {
      scrollTargets = ["viewport": nil]
    } else {
      scrollTargets = Dictionary(
        uniqueKeysWithValues: scrollElements.enumerated().map { index, element in
          ("scroll_\(index)", Optional(element.identity))
        })
    }

    let focused = observation.focusedField
    let textValues: [String: String?] = Dictionary(
      uniqueKeysWithValues: Array(textCandidates.prefix(AgentLimits.maximumChoiceOptions - 1))
        .enumerated().map { ("text_\($0.offset)", Optional($0.element)) } + [("NONE", nil)]
    )

    let operationCriteria = operationCriteria(
      hasTapTargets: !tapTargets.isEmpty,
      hasFocusedField: focused != nil && textValues.count > 1,
      hasScroll: !scrollTargets.isEmpty
    )
    var questions: [String: ChoiceQuestion] = [
      "operation": ChoiceQuestion(
        instructions:
          "Choose the single next bounded operation that best advances `goal` from the current observed UI. Choose DONE only when every requirement is visibly satisfied; choose BLOCKED when no offered operation can make progress.",
        criteria: operationCriteria
      )
    ]
    if !tapTargets.isEmpty {
      questions["tap_target"] = ChoiceQuestion(
        instructions:
          "Assuming the next operation is TAP, choose the one actionable element to tap.",
        criteria: Dictionary(
          uniqueKeysWithValues: actionable.enumerated().map { index, element in
            ("tap_\(index)", describe(element))
          })
      )
    }
    if !scrollTargets.isEmpty {
      questions["scroll_target"] = ChoiceQuestion(
        instructions:
          "Assuming the next operation is SCROLL_UP or SCROLL_DOWN, choose the scroll region that should move.",
        criteria: Dictionary(
          uniqueKeysWithValues: scrollTargets.map { key, identity in
            (
              key,
              identity.map { "\($0.role): \($0.label ?? $0.identifier ?? "unlabeled region")" }
                ?? "Root viewport"
            )
          })
      )
    }
    if focused != nil && textValues.count > 1 {
      questions["text_value"] = ChoiceQuestion(
        instructions:
          "Assuming the next operation is TYPE_TEXT, select the exact complete value appropriate for the focused field. Choose NONE if no candidate is the complete intended value.",
        criteria: Dictionary(
          uniqueKeysWithValues: textValues.map { key, value in
            (
              key,
              value.map { "Type this exact value unchanged: \($0)" }
                ?? "No supplied candidate is appropriate"
            )
          })
      )
    }

    func state(for visible: [String]) -> JSONValue {
      .object([
        "goal": .string(configuration.goal),
        "application": .object([
          "state": .string(observation.applicationState),
          "bundle_identifier": observation.bundleIdentifier.map(JSONValue.string) ?? .null
        ]),
        "visible_text": .array(visible.map(JSONValue.string)),
        "actionable_elements": .array(
          actionable.enumerated().map { index, element in
            .object([
              "id": .string("tap_\(index)"),
              "role": .string(element.role),
              "label": element.label.map(JSONValue.string) ?? .null,
              "value": element.value.map(JSONValue.string) ?? .null,
              "selected": element.selected.map(JSONValue.bool) ?? .null
            ])
          }),
        "focused_field": focused.map { field in
          .object([
            "role": .string(field.role),
            "label": field.label.map(JSONValue.string) ?? .null,
            "value": field.value.map(JSONValue.string) ?? .null,
            "editable": .bool(true),
            "secure": .bool(false)
          ])
        } ?? .null,
        "recent_actions": .array(
          history.suffix(AgentLimits.maximumHistoryEntries).map { entry in
            .object([
              "operation": .string(entry.operation.rawValue),
              "target": entry.target.map(JSONValue.string) ?? .null,
              "text_length": entry.textLength.map(JSONValue.int) ?? .null,
              "screen_changed": .bool(entry.screenChanged)
            ])
          })
      ])
    }

    var request = SystemOneRequest(
      state: state(for: visibleText), model: model, questions: questions)
    while try JSONEncoder().encode(request).count > AgentLimits.maximumEncodedRequestBytes,
      !visibleText.isEmpty
    {
      visibleText.removeLast()
      droppedVisibleText += 1
      request = SystemOneRequest(state: state(for: visibleText), model: model, questions: questions)
    }
    guard try JSONEncoder().encode(request).count <= AgentLimits.maximumEncodedRequestBytes else {
      throw AgentError.invalidConfiguration(
        "TypeSafe request exceeds \(AgentLimits.maximumEncodedRequestBytes) bytes after deterministic truncation"
      )
    }

    return RequestPlan(
      request: request,
      tapTargets: tapTargets,
      scrollTargets: scrollTargets,
      textValues: textValues,
      droppedVisibleText: droppedVisibleText,
      droppedTargets: droppedTargets
    )
  }

  private static func operationCriteria(
    hasTapTargets: Bool,
    hasFocusedField: Bool,
    hasScroll: Bool
  ) -> [String: String?] {
    var criteria: [String: String?] = [
      AgentOperation.wait.rawValue: "Wait briefly for the current UI to settle or load",
      AgentOperation.done.rawValue: "Every goal requirement is already visibly satisfied",
      AgentOperation.blocked.rawValue: "No offered operation can make progress toward the goal"
    ]
    if hasTapTargets {
      criteria[AgentOperation.tap.rawValue] = "Tap one currently actionable control"
    }
    if hasFocusedField {
      criteria[AgentOperation.typeText.rawValue] =
        "Type one exact candidate into the focused editable field"
    }
    if hasScroll {
      criteria[AgentOperation.scrollUp.rawValue] = "Move content down to reveal content above"
      criteria[AgentOperation.scrollDown.rawValue] = "Move content up to reveal content below"
    }
    return criteria
  }

  private static func describe(_ element: HierarchyElement) -> String {
    var parts = [element.role]
    if let label = element.label { parts.append("label: \(String(label.prefix(240)))") }
    if let value = element.value { parts.append("value: \(String(value.prefix(120)))") }
    if element.selected == true { parts.append("selected") }
    return parts.joined(separator: ", ")
  }
}
