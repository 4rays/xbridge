import Darwin
import Foundation
import XhammerCore

// MARK: - Daemonize

// Create a new session to detach from the controlling terminal.
Darwin.setsid()

// Redirect stdin to /dev/null
_ = Darwin.freopen("/dev/null", "r", Darwin.stdin)

// MARK: - Signal handling

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)

let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { exit(0) }
sigterm.resume()

let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { exit(0) }
sigint.resume()

// MARK: - Logging

_ = try? XhammerPaths.ensureDirectoryExists()

let logFileURL = XhammerPaths.logPath
if !FileManager.default.fileExists(atPath: logFileURL.path) {
  FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
}

let logFile: FileHandle
if let fh = FileHandle(forWritingAtPath: logFileURL.path) {
  fh.seekToEndOfFile()
  logFile = fh
} else {
  logFile = .standardError
}

let logger = Logger(label: "xhammerd", fileHandle: logFile)
logger.info("xhammerd starting (PID \(ProcessInfo.processInfo.processIdentifier))")

// MARK: - Run

let daemon = DaemonServer(logger: logger)

do {
  try await daemon.run()
} catch is CancellationError {
  logger.info("Cancelled, shutting down")
  await daemon.shutdown()
  exit(0)
} catch {
  logger.error("Fatal: \(error.localizedDescription)")
  exit(1)
}
