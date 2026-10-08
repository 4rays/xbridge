import CryptoKit
import Foundation
import XbridgeCore

public struct DecodedDeviceHubResult: Sendable {
  public let applicationState: String
  public let hierarchyPath: String
  public let screenshotPath: String?
  public let logsPath: String?

  public init(
    applicationState: String,
    hierarchyPath: String,
    screenshotPath: String?,
    logsPath: String?
  ) {
    self.applicationState = applicationState
    self.hierarchyPath = hierarchyPath
    self.screenshotPath = screenshotPath
    self.logsPath = logsPath
  }
}

public enum DeviceHubResultDecoder {
  public static func decode(_ value: JSONValue) throws -> DecodedDeviceHubResult {
    if let object = value.objectValue, let decoded = decodeObject(object) { return decoded }

    if let text = findJSONText(in: value), let data = text.data(using: .utf8),
      let nested = try? JSONDecoder().decode(JSONValue.self, from: data)
    {
      return try decode(nested)
    }

    throw AgentError.observation("Device Hub response did not contain a hierarchy path")
  }

  private static func decodeObject(_ object: [String: JSONValue]) -> DecodedDeviceHubResult? {
    if let hierarchyPath = object["hierarchyPath"]?.stringValue {
      return DecodedDeviceHubResult(
        applicationState: object["applicationState"]?.stringValue ?? "Unknown",
        hierarchyPath: hierarchyPath,
        screenshotPath: object["screenshotPath"]?.stringValue,
        logsPath: object["logsPath"]?.stringValue
      )
    }
    for key in ["result", "structuredContent", "data"] {
      if let nested = object[key], let decoded = try? decode(nested) { return decoded }
    }
    return nil
  }

  private static func findJSONText(in value: JSONValue) -> String? {
    switch value {
    case .string(let text): return text
    case .array(let values):
      return values.lazy.compactMap(findJSONText).first
    case .object(let object):
      if let text = object["text"]?.stringValue { return text }
      if let content = object["content"] { return findJSONText(in: content) }
      return object.values.lazy.compactMap(findJSONText).first
    default: return nil
    }
  }
}

public struct HierarchyParser: Sendable {
  public init() {}

  public func parse(_ source: String) throws -> (
    bundleIdentifier: String?, elements: [HierarchyElement]
  ) {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let bundleIdentifier = lines.first { $0.hasPrefix("Application bundle identifier:") }?
      .split(separator: ":", maxSplits: 1).last.map {
        String($0).trimmingCharacters(in: .whitespaces)
      }
    var parentRoles: [Int: String] = [:]
    var siblingIndexes: [String: Int] = [:]
    var elements: [HierarchyElement] = []

    for line in lines {
      guard let parsed = parseElementLine(line) else { continue }
      let parentRole = parsed.depth > 0 ? parentRoles[parsed.depth - 1] : nil
      parentRoles[parsed.depth] = parsed.role
      parentRoles = parentRoles.filter { $0.key <= parsed.depth }
      let parentPath = elements.last(where: { $0.depth < parsed.depth })?.path ?? "root"
      let siblingKey = "\(parentPath)/\(parsed.role)"
      let siblingIndex = siblingIndexes[siblingKey, default: 0]
      siblingIndexes[siblingKey] = siblingIndex + 1
      let path = "\(parentPath)/\(parsed.role)[\(siblingIndex)]"

      elements.append(
        HierarchyElement(
          path: path,
          depth: parsed.depth,
          role: parsed.role,
          identifier: capture("identifier", in: parsed.rest),
          label: capture("label", in: parsed.rest),
          value: captureValue(in: parsed.rest),
          frame: captureFrame(in: parsed.rest),
          hitPoint: capturePoint(named: "hitPoint", in: parsed.rest),
          enabled: parsed.rest.contains(", Disabled") || parsed.rest.contains(", NotHittable")
            ? false : nil,
          selected: parsed.rest.contains(", Selected") ? true : nil,
          focused: parsed.rest.contains(", Focused") || parsed.rest.contains("Keyboard Focused")
            ? true : nil,
          secure: secureState(role: parsed.role, text: parsed.rest),
          editable: editableState(role: parsed.role, text: parsed.rest),
          hidden: parsed.rest.contains(", Hidden") ? true : nil,
          traits: flags(in: parsed.rest),
          rawSource: line,
          parentRole: parentRole
        )
      )
    }

    guard !elements.isEmpty else { throw AgentError.observation("Hierarchy contains no elements") }
    return (bundleIdentifier, elements)
  }

  private func parseElementLine(_ line: String) -> (depth: Int, role: String, rest: String)? {
    let spaces = line.prefix { $0 == " " }.count
    guard spaces > 0 else { return nil }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let comma = trimmed.firstIndex(of: ",") else { return nil }
    let role = String(trimmed[..<comma])
    guard role.range(of: #"^[A-Za-z][A-Za-z0-9]*$"#, options: .regularExpression) != nil else {
      return nil
    }
    return (spaces - 1, role, String(trimmed[trimmed.index(after: comma)...]))
  }

  private func capture(_ name: String, in text: String) -> String? {
    guard let range = text.range(of: "\(name): '") else { return nil }
    let start = range.upperBound
    var index = start
    var escaped = false
    while index < text.endIndex {
      let character = text[index]
      if character == "'" && !escaped { return String(text[start..<index]) }
      escaped = character == "\\" && !escaped
      if character != "\\" { escaped = false }
      index = text.index(after: index)
    }
    return nil
  }

  private func captureValue(in text: String) -> String? {
    guard let range = text.range(of: "value: ") else { return nil }
    let suffix = text[range.upperBound...]
    let delimiters = [
      ", hitPoint:", ", Selected", ", Focused", ", Keyboard Focused", ", Secure",
      ", Editable", ", Disabled", ", Hidden", ", NotHittable"
    ]
    let end = delimiters.compactMap { suffix.range(of: $0)?.lowerBound }.min() ?? suffix.endIndex
    return String(suffix[..<end]).trimmingCharacters(in: .whitespaces)
  }

  private func captureFrame(in text: String) -> AgentRect? {
    let pattern = #"\{\{(-?[0-9.]+), (-?[0-9.]+)\}, \{(-?[0-9.]+), (-?[0-9.]+)\}\}"#
    guard let groups = captures(pattern, in: text), groups.count == 4,
      let x = Double(groups[0]), let y = Double(groups[1]),
      let width = Double(groups[2]), let height = Double(groups[3])
    else { return nil }
    return AgentRect(x: x, y: y, width: width, height: height)
  }

  private func capturePoint(named name: String, in text: String) -> AgentPoint? {
    let pattern = #"\#(name): \{(-?[0-9.]+), (-?[0-9.]+)\}"#
    guard let groups = captures(pattern, in: text), groups.count == 2,
      let x = Double(groups[0]), let y = Double(groups[1])
    else { return nil }
    return AgentPoint(x: x, y: y)
  }

  private func captures(_ pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    return (1..<match.numberOfRanges).compactMap { index in
      guard let range = Range(match.range(at: index), in: text) else { return nil }
      return String(text[range])
    }
  }

  private func flags(in text: String) -> [String] {
    ["Disabled", "Selected", "Focused", "Secure", "Hidden", "NotHittable"]
      .filter { text.contains(", \($0)") }
  }

  private func secureState(role: String, text: String) -> Bool? {
    if role == "SecureTextField" || text.contains(", Secure") { return true }
    if role == "TextField" || role == "TextView" { return false }
    return nil
  }

  private func editableState(role: String, text: String) -> Bool? {
    if ["TextField", "SecureTextField", "TextView", "SearchField"].contains(role) { return true }
    if text.contains(", Editable") { return true }
    return nil
  }
}

public enum ObservationFactory {
  public static func make(
    decoded: DecodedDeviceHubResult,
    hierarchy: String,
    capturedAt: Date = Date(),
    parser: HierarchyParser = HierarchyParser()
  ) throws -> DeviceObservation {
    let parsed = try parser.parse(hierarchy)
    let fingerprint = fingerprint(
      applicationState: decoded.applicationState,
      bundleIdentifier: parsed.bundleIdentifier,
      elements: parsed.elements
    )
    return DeviceObservation(
      applicationState: decoded.applicationState,
      bundleIdentifier: parsed.bundleIdentifier,
      capturedAt: capturedAt,
      artifacts: DeviceHubArtifacts(
        hierarchyPath: decoded.hierarchyPath,
        screenshotPath: decoded.screenshotPath,
        logsPath: decoded.logsPath
      ),
      hierarchy: hierarchy,
      elements: parsed.elements,
      fingerprint: fingerprint
    )
  }

  public static func fingerprint(
    applicationState: String,
    bundleIdentifier: String?,
    elements: [HierarchyElement]
  ) -> String {
    let stable = elements.map {
      [
        $0.path, $0.role, $0.identifier ?? "", $0.label ?? "", $0.value ?? "",
        $0.enabled.map(String.init) ?? "", $0.selected.map(String.init) ?? "",
        $0.focused.map(String.init) ?? ""
      ].joined(separator: "|")
    }.joined(separator: "\n")
    let input = "\(applicationState)\n\(bundleIdentifier ?? "")\n\(stable)"
    return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
