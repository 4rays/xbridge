import Foundation
import Testing

@testable import XbridgeDeviceAgent

@Suite struct TracingTests {
  @Test func traceDirectoryAndFilesAreOwnerOnly() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("xbridge-trace-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let trace = try LocalTraceWriter(directory: root.path)
    try await trace.record("event", value: ["safe": "value"])

    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
    let fileAttributes = try FileManager.default.attributesOfItem(
      atPath: root.appendingPathComponent("001-event.json").path
    )
    #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)
    #expect(fileAttributes[.posixPermissions] as? Int == 0o600)
  }
}
