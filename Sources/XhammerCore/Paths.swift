import Foundation

public enum XhammerPaths {
  public static var supportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("xhammer", isDirectory: true)
  }

  public static var socketPath: URL {
    supportDirectory.appendingPathComponent("daemon.sock")
  }

  public static var pidPath: URL {
    supportDirectory.appendingPathComponent("daemon.pid")
  }

  public static var logPath: URL {
    supportDirectory.appendingPathComponent("daemon.log")
  }

  public static var statePath: URL {
    supportDirectory.appendingPathComponent("state.json")
  }

  public static func ensureDirectoryExists() throws {
    try FileManager.default.createDirectory(
      at: supportDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }
}
