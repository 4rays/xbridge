import Foundation
import Testing
import XbridgeCore

@testable import XbridgeDeviceAgent

@Suite struct HierarchyParserTests {
  @Test func parsesCapturedHierarchyAndSeparatesEvidenceFromActions() throws {
    let source = try TestSupport.fixture("circle-discover-hierarchy")
    let parsed = try HierarchyParser().parse(source)

    #expect(parsed.bundleIdentifier == "com.example.Circle")
    #expect(parsed.elements.contains { $0.role == "StaticText" && $0.label == "Trending" })
    #expect(!parsed.elements.contains { $0.role == "StaticText" && $0.isActionable })
    #expect(
      parsed.elements.contains { $0.role == "Button" && $0.label == "Search" && $0.isActionable })
    #expect(parsed.elements.filter(\.isScrollRegion).count == 2)
    #expect(parsed.elements.first { $0.label == "Explore" }?.selected == true)
  }

  @Test func conservativelyParsesFieldsStatesDuplicatesAndUnknownProperties() throws {
    let parsed = try HierarchyParser().parse(TestSupport.fixture("controls-hierarchy"))
    let displayName = try #require(parsed.elements.first { $0.identifier == "display-name" })
    let password = try #require(parsed.elements.first { $0.identifier == "password" })
    let disabled = try #require(parsed.elements.first { $0.identifier == "delete" })

    #expect(displayName.isFocusedEditableField)
    #expect(displayName.rawSource.contains("FutureProperty"))
    #expect(password.secure == true)
    #expect(!password.isFocusedEditableField)
    #expect(disabled.enabled == false)
    #expect(!disabled.isActionable)
    #expect(parsed.elements.filter { $0.label == "Save" }.count == 2)
    #expect(parsed.elements.contains { $0.label?.contains("東京") == true })
  }

  @Test func rejectsMalformedHierarchy() {
    #expect(throws: AgentError.self) { try HierarchyParser().parse("not a hierarchy") }
  }

  @Test func decodesStructuredAndTextWrappedResponses() throws {
    let direct: JSONValue = [
      "applicationState": "RunningForeground",
      "hierarchyPath": "/tmp/hierarchy.txt",
      "screenshotPath": "/tmp/screenshot.png"
    ]
    let decoded = try DeviceHubResultDecoder.decode(direct)
    #expect(decoded.applicationState == "RunningForeground")
    #expect(decoded.hierarchyPath == "/tmp/hierarchy.txt")

    let wrapped: JSONValue = [
      "content": .array([
        [
          "type": "text",
          "text": "{\"applicationState\":\"NotRun\",\"hierarchyPath\":\"/tmp/h.txt\"}"
        ]
      ])
    ]
    #expect(try DeviceHubResultDecoder.decode(wrapped).hierarchyPath == "/tmp/h.txt")
  }

  @Test func fingerprintIgnoresArtifactPathsAndRawFormatting() throws {
    let source = try TestSupport.fixture("circle-discover-hierarchy")
    let first = try ObservationFactory.make(
      decoded: DecodedDeviceHubResult(
        applicationState: "RunningForeground",
        hierarchyPath: "/tmp/one.txt",
        screenshotPath: "/tmp/one.png",
        logsPath: nil
      ),
      hierarchy: source
    )
    let second = try ObservationFactory.make(
      decoded: DecodedDeviceHubResult(
        applicationState: "RunningForeground",
        hierarchyPath: "/tmp/two.txt",
        screenshotPath: "/tmp/two.png",
        logsPath: nil
      ),
      hierarchy: source.replacingOccurrences(
        of: "Application, pid: 1000", with: "Application, pid: 9999")
    )
    #expect(first.fingerprint == second.fingerprint)
  }

  @Test func parsesUIKitKeyboardFocusedSearchField() throws {
    let observation = try TestSupport.observation(fixture: "settings-search-hierarchy")
    let field = try #require(observation.focusedField)
    #expect(field.role == "SearchField")
    #expect(field.focused == true)
    #expect(field.editable == true)
    #expect(field.value == "General")
    #expect(observation.scrollRegions.map(\.role) == ["CollectionView"])
  }
}
