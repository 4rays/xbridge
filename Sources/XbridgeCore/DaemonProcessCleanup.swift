import Darwin
import Foundation

public struct DaemonCleanupResult: Sendable {
  public let terminatedPIDs: [Int32]
  public let removedPIDFile: Bool
  public let removedSocketFile: Bool

  public var didCleanup: Bool {
    !terminatedPIDs.isEmpty || removedPIDFile || removedSocketFile
  }
}

public enum DaemonProcessCleanup {
  public static func cleanupExistingDaemons(
    excluding excludedPID: Int32? = nil,
    log: (@Sendable (String) -> Void)? = nil
  ) -> DaemonCleanupResult {
    let pids = daemonPIDs(excluding: excludedPID)

    for pid in pids where processExists(pid) {
      log?("Terminating existing xbridged PID \(pid)")
      Darwin.kill(pid, SIGTERM)
    }

    waitForExit(pids: pids, timeout: 1.0)

    for pid in pids where processExists(pid) {
      log?("Killing unresponsive xbridged PID \(pid)")
      Darwin.kill(pid, SIGKILL)
    }

    waitForExit(pids: pids, timeout: 0.5)

    let removedPIDFile = removeFileIfPresent(XbridgePaths.pidPath)
    let removedSocketFile = removeFileIfPresent(XbridgePaths.socketPath)

    return DaemonCleanupResult(
      terminatedPIDs: pids.sorted(),
      removedPIDFile: removedPIDFile,
      removedSocketFile: removedSocketFile
    )
  }

  public static func removeStaleStateFiles() -> DaemonCleanupResult {
    DaemonCleanupResult(
      terminatedPIDs: [],
      removedPIDFile: removeFileIfPresent(XbridgePaths.pidPath),
      removedSocketFile: removeFileIfPresent(XbridgePaths.socketPath)
    )
  }

  private static func daemonPIDs(excluding excludedPID: Int32?) -> [Int32] {
    var pids = Set<Int32>()

    if let pid = readPIDFile() {
      pids.insert(pid)
    }

    for pid in findRunningDaemonPIDs() {
      pids.insert(pid)
    }

    if let excludedPID {
      pids.remove(excludedPID)
    }

    return pids.filter { $0 > 0 }
  }

  private static func readPIDFile() -> Int32? {
    guard let content = try? String(contentsOf: XbridgePaths.pidPath, encoding: .utf8) else {
      return nil
    }
    return Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func findRunningDaemonPIDs() -> [Int32] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-x", "-o", "pid=", "-o", "comm="]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle(forWritingAtPath: "/dev/null")

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
      return []
    }

    return output.split(separator: "\n").compactMap { line -> Int32? in
      let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
      guard parts.count == 2, let pid = Int32(parts[0]) else {
        return nil
      }

      let command = String(parts[1])
      guard URL(fileURLWithPath: command).lastPathComponent == "xbridged" else {
        return nil
      }

      return pid
    }
  }

  private static func processExists(_ pid: Int32) -> Bool {
    if Darwin.kill(pid, 0) == 0 {
      return true
    }
    return Darwin.errno != ESRCH
  }

  private static func waitForExit(pids: [Int32], timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !pids.contains(where: processExists) {
        return
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
  }

  private static func removeFileIfPresent(_ url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return false
    }
    do {
      try FileManager.default.removeItem(at: url)
      return true
    } catch {
      return false
    }
  }
}
