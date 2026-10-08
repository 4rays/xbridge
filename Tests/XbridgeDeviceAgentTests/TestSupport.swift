import Foundation
import Testing

@testable import XbridgeDeviceAgent

enum TestSupport {
  static func fixture(_ name: String, extension ext: String = "txt") throws -> String {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  static func observation(
    fixture name: String = "controls-hierarchy",
    fingerprintOverride: String? = nil
  ) throws -> DeviceObservation {
    let hierarchy = try fixture(name)
    let decoded = DecodedDeviceHubResult(
      applicationState: "RunningForeground",
      hierarchyPath: "/tmp/\(name).txt",
      screenshotPath: "/tmp/screenshot.png",
      logsPath: nil
    )
    let observation = try ObservationFactory.make(
      decoded: decoded,
      hierarchy: hierarchy,
      capturedAt: Date(timeIntervalSince1970: 1)
    )
    guard let fingerprintOverride else { return observation }
    return DeviceObservation(
      applicationState: observation.applicationState,
      bundleIdentifier: observation.bundleIdentifier,
      capturedAt: observation.capturedAt,
      artifacts: observation.artifacts,
      hierarchy: observation.hierarchy,
      elements: observation.elements,
      fingerprint: fingerprintOverride
    )
  }

  static func observation(replacing old: String, with new: String) throws -> DeviceObservation {
    let hierarchy = try fixture("controls-hierarchy").replacingOccurrences(of: old, with: new)
    return try ObservationFactory.make(
      decoded: DecodedDeviceHubResult(
        applicationState: "RunningForeground",
        hierarchyPath: "/tmp/controls-hierarchy.txt",
        screenshotPath: nil,
        logsPath: nil
      ),
      hierarchy: hierarchy,
      capturedAt: Date(timeIntervalSince1970: 1)
    )
  }

  static func answer(
    choice: String,
    keys: [String],
    confidence: Double = 1,
    override: [String: Double]? = nil
  ) -> ChoiceAnswer {
    var probabilities = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0.0) })
    probabilities[choice] = 1
    return ChoiceAnswer(
      type: "choice",
      choice: choice,
      probabilities: override ?? probabilities,
      confidence: confidence
    )
  }
}
