import Darwin
import Foundation
import XbridgeCore

/// Manages the xcrun mcpbridge child process, including launch, I/O, and restart.
actor BridgeProcess {
  enum State: Sendable {
    case stopped
    case starting
    case running(pid: Int32)
    case failed(String)
  }

  enum TerminationCause: Sendable, CustomStringConvertible {
    case duringToolCall
    case duringHandshake
    case idle
    var description: String {
      switch self {
      case .duringToolCall: return "duringToolCall"
      case .duringHandshake: return "duringHandshake"
      case .idle: return "idle"
      }
    }
  }

  private(set) var state: State = .stopped
  private(set) var lastTerminationCause: TerminationCause = .idle
  private var stdinFD: Int32 = -1
  private var nextRequestID = 1
  private var pendingResponses: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
  private var pendingMethods: [Int: String] = [:]
  private var terminationWaiters: [CheckedContinuation<Void, Never>] = []
  private var readTask: Task<Void, Never>?
  private let logger: Logger

  // Keep process and pipes alive via @unchecked Sendable container
  private nonisolated(unsafe) var handles: BridgeHandles?

  init(logger: Logger) {
    self.logger = logger
  }

  var isRunning: Bool {
    if case .running = state {
      return handles?.process.isRunning ?? false
    }
    return false
  }

  func nextID() -> Int {
    defer { nextRequestID += 1 }
    return nextRequestID
  }

  // MARK: - Lifecycle

  func start() async throws {
    guard case .stopped = state else { return }
    state = .starting

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["mcpbridge"]

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    process.terminationHandler = { @Sendable [weak self] _ in
      Task { await self?.handleTermination() }
    }

    do {
      try process.run()
    } catch {
      state = .failed(error.localizedDescription)
      throw error
    }

    handles = BridgeHandles(
      process: process,
      stdinPipe: stdinPipe,
      stdoutPipe: stdoutPipe,
      stderrPipe: stderrPipe
    )
    stdinFD = stdinPipe.fileHandleForWriting.fileDescriptor
    state = .running(pid: process.processIdentifier)
    logger.info("Bridge started with PID \(process.processIdentifier)")

    startStderrReader(fd: stderrPipe.fileHandleForReading.fileDescriptor)
    startStdoutReader(fd: stdoutPipe.fileHandleForReading.fileDescriptor)
  }

  func stop() async {
    if let process = handles?.process, process.isRunning {
      try? handles?.stdinPipe.fileHandleForWriting.close()
      let gracefulDeadline = Date().addingTimeInterval(1.0)
      while process.isRunning, Date() < gracefulDeadline {
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
      if process.isRunning {
        process.terminate()
        let termDeadline = Date().addingTimeInterval(1.0)
        while process.isRunning, Date() < termDeadline {
          try? await Task.sleep(nanoseconds: 50_000_000)
        }
      }
      if process.isRunning {
        Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
    }
    handles = nil
    stdinFD = -1
    state = .stopped
    readTask?.cancel()
    readTask = nil
    failPending(XbridgeError.bridgeNotRunning)
  }

  // MARK: - Send

  /// Send a request and await the correlated response.
  func send(_ request: MCPRequest) async throws -> MCPResponse {
    guard case .running = state, stdinFD >= 0 else {
      throw XbridgeError.bridgeNotRunning
    }
    let data = try JSONEncoder().encode(request)
    guard let line = String(data: data, encoding: .utf8) else {
      throw XbridgeError.decodingError("Could not encode MCP request")
    }
    let lineData = Data((line + "\n").utf8)

    return try await withCheckedThrowingContinuation { continuation in
      var failed = false
      lineData.withUnsafeBytes { ptr in
        var offset = 0
        while offset < ptr.count {
          let n = Darwin.write(stdinFD, ptr.baseAddress! + offset, ptr.count - offset)
          if n <= 0 { failed = true; break }
          offset += n
        }
      }
      if failed {
        continuation.resume(throwing: XbridgeError.writeFailed)
      } else {
        pendingResponses[request.id] = continuation
        pendingMethods[request.id] = request.method
      }
    }
  }

  /// Write a notification line that expects no response.
  func sendRaw(_ line: String) throws {
    guard stdinFD >= 0 else { throw XbridgeError.bridgeNotRunning }
    let lineData = Data((line + "\n").utf8)
    lineData.withUnsafeBytes { ptr in
      var offset = 0
      while offset < ptr.count {
        let n = Darwin.write(stdinFD, ptr.baseAddress! + offset, ptr.count - offset)
        if n <= 0 { break }
        offset += n
      }
    }
  }

  // MARK: - Response delivery

  private func deliverResponse(_ response: MCPResponse) {
    guard let id = response.id else { return }
    pendingMethods.removeValue(forKey: id)
    if let cont = pendingResponses.removeValue(forKey: id) {
      cont.resume(returning: response)
    } else {
      logger.debug("Unmatched response id \(id)")
    }
  }

  /// Suspend until the bridge process stops (returns immediately if already stopped).
  func waitUntilTerminated() async {
    if case .stopped = state { return }
    if case .failed = state { return }
    await withCheckedContinuation { cont in
      terminationWaiters.append(cont)
    }
  }

  private func handleTermination() {
    guard case .running = state else { return }
    // Compute cause before failing pending so callers can read it immediately after resuming.
    let methods = Set(pendingMethods.values)
    lastTerminationCause = methods.contains("tools/call") ? .duringToolCall
      : (!methods.isEmpty ? .duringHandshake : .idle)
    logger.warning("Bridge process terminated (cause: \(lastTerminationCause))")
    state = .stopped
    handles = nil
    stdinFD = -1
    readTask?.cancel()
    readTask = nil
    failPending(XbridgeError.bridgeNotRunning)
    for cont in terminationWaiters { cont.resume() }
    terminationWaiters.removeAll()
  }

  private func failPending(_ error: Error) {
    for (_, cont) in pendingResponses {
      cont.resume(throwing: error)
    }
    pendingResponses.removeAll()
    pendingMethods.removeAll()
  }

  // MARK: - I/O readers

  private func startStdoutReader(fd: Int32) {
    readTask = Task { [weak self] in
      for await response in Self.responseStream(fd: fd) {
        await self?.deliverResponse(response)
      }
      await self?.handleTermination()
    }
  }

  private func startStderrReader(fd: Int32) {
    Task { [logger] in
      for await line in Self.lineStream(fd: fd) {
        logger.info("[bridge] \(line)")
      }
    }
  }

  /// Produces decoded MCPResponse values from a line-oriented stdout fd.
  private static func responseStream(fd: Int32) -> AsyncStream<MCPResponse> {
    AsyncStream { continuation in
      DispatchQueue.global(qos: .userInteractive).async {
        var buffer = Data()
        var byte = [UInt8](repeating: 0, count: 1)
        while true {
          let n = Darwin.read(fd, &byte, 1)
          if n <= 0 { continuation.finish(); return }
          if byte[0] == 0x0A {
            if !buffer.isEmpty,
              let response = try? JSONDecoder().decode(MCPResponse.self, from: buffer)
            {
              continuation.yield(response)
            }
            buffer.removeAll(keepingCapacity: true)
          } else {
            buffer.append(byte[0])
          }
        }
      }
    }
  }

  /// Produces raw text lines from a fd (used for stderr).
  private static func lineStream(fd: Int32) -> AsyncStream<String> {
    AsyncStream { continuation in
      DispatchQueue.global(qos: .background).async {
        var buffer = Data()
        var byte = [UInt8](repeating: 0, count: 1)
        while true {
          let n = Darwin.read(fd, &byte, 1)
          if n <= 0 { continuation.finish(); return }
          if byte[0] == 0x0A {
            if let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
              continuation.yield(line)
            }
            buffer.removeAll(keepingCapacity: true)
          } else {
            buffer.append(byte[0])
          }
        }
      }
    }
  }
}

// MARK: - Helpers

/// Wraps non-Sendable OS handles; actor isolation provides the required synchronization.
private struct BridgeHandles: @unchecked Sendable {
  let process: Process
  let stdinPipe: Pipe
  let stdoutPipe: Pipe
  let stderrPipe: Pipe
}
