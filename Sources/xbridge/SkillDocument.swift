import Foundation

/// Reads the skill shipped with this installation; never contacts the daemon or the network.
enum SkillDocument {
  static func contents() throws -> Data {
    let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath()
    let installed = executable.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("share/xbridge/xbridge-skill.md")
    if FileManager.default.fileExists(atPath: installed.path) {
      return try Data(contentsOf: installed)
    }

    #if DEBUG
      // swift run / swift build from a source checkout before `make install`.
      let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("skills/xbridge/SKILL.md")
      if FileManager.default.fileExists(atPath: source.path) {
        return try Data(contentsOf: source)
      }
    #endif

    throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: installed.path])
  }
}
