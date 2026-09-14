import Darwin
import Foundation
import XbridgeCore

// MARK: - Daemonize

// Create a new session to detach from the controlling terminal.
Darwin.setsid()

// Redirect stdin to /dev/null
_ = Darwin.freopen("/dev/null", "r", Darwin.stdin)

// MARK: - Logging

_ = try? XbridgePaths.ensureDirectoryExists()

let logFileURL = XbridgePaths.logPath
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

let logger = Logger(label: "xbridged", fileHandle: logFile)
logger.info("xbridged starting (PID \(ProcessInfo.processInfo.processIdentifier))")

// MARK: - Args

func parseDeveloperDir() -> String? {
  let args = Array(CommandLine.arguments.dropFirst())
  if let idx = args.firstIndex(of: "--xcode-path"), args.index(after: idx) < args.endIndex {
    let raw = args[args.index(after: idx)]
    // Accept either .app path or a full Contents/Developer path
    if raw.hasSuffix(".app") {
      return raw + "/Contents/Developer"
    }
    return raw
  }
  return nil
}

let developerDir = parseDeveloperDir()

// MARK: - Run

let daemon = DaemonServer(logger: logger, developerDir: developerDir)

// MARK: - Signal handling

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)

let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler {
  Task {
    await daemon.shutdown()
    exit(0)
  }
}
sigterm.resume()

let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
  Task {
    await daemon.shutdown()
    exit(0)
  }
}
sigint.resume()

do {
  try await daemon.run()
} catch is CancellationError {
  logger.info("Cancelled, shutting down")
  await daemon.shutdown()
  exit(0)
} catch {
  logger.error("Fatal: \(error.localizedDescription)")
  await daemon.shutdown()
  exit(1)
}
