import Foundation

public enum TargetResolver {
  public static func resolve(
    _ identity: SemanticIdentity,
    in observation: DeviceObservation
  ) -> HierarchyElement? {
    let roleMatches = observation.elements.filter { $0.role == identity.role }
    let exactPath = roleMatches.filter { element in
      element.path == identity.path && semanticsMatch(element, identity: identity)
    }
    if exactPath.count == 1 { return exactPath[0] }

    let semanticMatches = roleMatches.filter { semanticsMatch($0, identity: identity) }
    return semanticMatches.count == 1 ? semanticMatches[0] : nil
  }

  public static func resolveFieldForReadback(
    _ identity: SemanticIdentity,
    in observation: DeviceObservation
  ) -> HierarchyElement? {
    let candidates = observation.elements.filter { element in
      guard element.role == identity.role, element.label == identity.label else { return false }
      if let identifier = identity.identifier, element.identifier != identifier { return false }
      if let parentRole = identity.parentRole, element.parentRole != parentRole { return false }
      return element.editable == true && element.secure != true
    }
    let exactPath = candidates.filter { $0.path == identity.path }
    if exactPath.count == 1 { return exactPath[0] }
    return candidates.count == 1 ? candidates[0] : nil
  }

  private static func semanticsMatch(
    _ element: HierarchyElement,
    identity: SemanticIdentity
  ) -> Bool {
    if let identifier = identity.identifier, element.identifier != identifier { return false }
    if element.label != identity.label { return false }
    if element.value != identity.value { return false }
    if let parentRole = identity.parentRole, element.parentRole != parentRole { return false }
    return true
  }
}

public enum DeviceCommandBuilder {
  public static func tap(_ element: HierarchyElement) throws -> String {
    guard element.isActionable else { throw AgentError.staleTarget }
    let point = element.hitPoint ?? element.frame?.center
    guard let point else { throw AgentError.staleTarget }
    return "t \(format(point.x)) \(format(point.y))"
  }

  public static func typeText(_ text: String, field: HierarchyElement) throws -> String {
    guard field.isFocusedEditableField, TextCandidates.isSupported(text) else {
      throw AgentError.unsupportedText
    }
    return "sender keyboard kbd \(text)"
  }

  public static func scroll(
    _ operation: AgentOperation,
    region: HierarchyElement?,
    observation: DeviceObservation
  ) throws -> String {
    guard operation == .scrollUp || operation == .scrollDown else {
      throw AgentError.invalidConfiguration("Invalid scroll operation")
    }
    let frame = region?.frame ?? rootViewport(in: observation)
    guard let frame, frame.width > 0, frame.height > 0 else { throw AgentError.staleTarget }
    let x = frame.x + frame.width / 2
    let upper = frame.y + frame.height * 0.3
    let lower = frame.y + frame.height * 0.7
    let startY = operation == .scrollDown ? lower : upper
    let endY = operation == .scrollDown ? upper : lower
    return "t \(format(x)) \(format(startY)) f \(format(x)) \(format(endY)) 0.3"
  }

  private static func rootViewport(in observation: DeviceObservation) -> AgentRect? {
    observation.elements.first { $0.role == "Window" && $0.frame != nil }?.frame
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.1f", value)
  }
}
