import Darwin
import Foundation
import XbridgeCore

/// Connects to the xbridged daemon and sends a single request, returning the response.
struct DaemonClient {
  private let socketPath: String

  init(socketPath: String = XbridgePaths.socketPath.path) {
    self.socketPath = socketPath
  }

  // MARK: - Send

  func send(_ request: LocalRPCRequest, autoStart: Bool = true) throws -> LocalRPCResponse {
    let fd = try connectOrSpawn(autoStart: autoStart)
    defer { Darwin.close(fd) }

    let data = try JSONEncoder().encode(request)
    guard let line = String(data: data, encoding: .utf8) else {
      throw XbridgeError.decodingError("Failed to encode request")
    }

    guard writeLine(line, fd: fd) else {
      throw XbridgeError.writeFailed
    }

    guard let responseLine = readLine(fd: fd), !responseLine.isEmpty else {
      throw XbridgeError.invalidResponse("Empty response from daemon")
    }
    guard let responseData = responseLine.data(using: .utf8) else {
      throw XbridgeError.decodingError("Invalid UTF-8 in response")
    }

    return try JSONDecoder().decode(LocalRPCResponse.self, from: responseData)
  }

  // MARK: - Connection

  private func connectOrSpawn(autoStart: Bool) throws -> Int32 {
    // Try connecting first
    if let fd = try? connect() { return fd }

    guard autoStart else {
      throw XbridgeError.daemonNotRunning
    }

    // Spawn daemon and retry
    try spawnDaemon()

    for delay in [0.2, 0.4, 0.8, 1.6] {
      Thread.sleep(forTimeInterval: delay)
      if let fd = try? connect() { return fd }
    }
    throw XbridgeError.daemonNotRunning
  }

  private func connect() throws -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw XbridgeError.socketError("socket() failed: \(errnoString())")
    }

    var addr = sockaddr_un()
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { dst in
      socketPath.withCString { src in
        _ = Darwin.memcpy(dst, src, min(socketPath.utf8.count + 1, 104))
      }
    }

    let result = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
        Darwin.connect(fd, sptr, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }

    guard result == 0 else {
      Darwin.close(fd)
      throw XbridgeError.connectionFailed(errnoString())
    }
    return fd
  }

  private func spawnDaemon() throws {
    _ = DaemonProcessCleanup.cleanupExistingDaemons { message in
      fputs("\(message)\n", stderr)
    }

    let daemonURL = findDaemonExecutable()
    guard let daemonURL, FileManager.default.isExecutableFile(atPath: daemonURL.path) else {
      throw XbridgeError.connectionFailed(
        "Cannot find xbridged. Make sure it is installed alongside xbridge."
      )
    }

    fputs("Starting xbridged...\n", stderr)

    let process = Process()
    process.executableURL = daemonURL
    process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
    process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
    process.standardError = FileHandle(forWritingAtPath: "/dev/null")

    do {
      try process.run()
    } catch {
      throw XbridgeError.connectionFailed("Failed to start xbridged: \(error.localizedDescription)")
    }
  }

  private func findDaemonExecutable() -> URL? {
    // Look in the same directory as the xhammer binary
    let selfPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let sibling = selfPath.deletingLastPathComponent().appendingPathComponent("xbridged")
    if FileManager.default.fileExists(atPath: sibling.path) {
      return sibling
    }
    // Search PATH
    let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
      .split(separator: ":")
      .map(String.init)
    for dir in pathDirs {
      let candidate = URL(fileURLWithPath: dir).appendingPathComponent("xbridged")
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }

  private func errnoString() -> String {
    String(cString: Darwin.strerror(Darwin.errno))
  }
}

// MARK: - POSIX I/O (client side)

private func readLine(fd: Int32) -> String? {
  var buffer = Data()
  var byte = [UInt8](repeating: 0, count: 1)
  while true {
    let n = Darwin.read(fd, &byte, 1)
    if n <= 0 { return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8) }
    if byte[0] == 0x0A { return String(data: buffer, encoding: .utf8) }
    buffer.append(byte[0])
  }
}

@discardableResult
private func writeLine(_ s: String, fd: Int32) -> Bool {
  let data = Data((s + "\n").utf8)
  var offset = 0
  return data.withUnsafeBytes { ptr in
    while offset < ptr.count {
      let n = Darwin.write(fd, ptr.baseAddress! + offset, ptr.count - offset)
      if n <= 0 { return false }
      offset += n
    }
    return true
  }
}
