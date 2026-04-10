import Foundation
import XhammerCore

/// Persists daemon state (PID, health) to the support directory.
actor StateStore {
  private let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  func writePID(_ pid: Int32) {
    do {
      try XhammerPaths.ensureDirectoryExists()
      try String(pid).write(to: XhammerPaths.pidPath, atomically: true, encoding: .utf8)
    } catch {
      logger.warning("Failed to write PID file: \(error.localizedDescription)")
    }
  }

  func readPID() -> Int32? {
    guard let content = try? String(contentsOf: XhammerPaths.pidPath, encoding: .utf8) else {
      return nil
    }
    return Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  func removePID() {
    try? FileManager.default.removeItem(at: XhammerPaths.pidPath)
  }

  func removeSocket() {
    try? FileManager.default.removeItem(at: XhammerPaths.socketPath)
  }
}
