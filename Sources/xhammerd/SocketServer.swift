import Darwin
import Foundation
import XhammerCore

/// Listens on a Unix domain socket and dispatches each accepted connection to a handler.
actor SocketServer {
  private nonisolated(unsafe) var serverFD: Int32 = -1
  private var acceptTask: Task<Void, Never>?
  private nonisolated let connectionHandler: @Sendable (Int32) async -> Void
  private let logger: Logger

  init(logger: Logger, connectionHandler: @escaping @Sendable (Int32) async -> Void) {
    self.logger = logger
    self.connectionHandler = connectionHandler
  }

  // MARK: - Start / Stop

  func start(socketPath: String) throws {
    // Clean up any stale socket file
    Darwin.unlink(socketPath)

    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw XhammerError.socketError("socket() failed: \(Self.errnoString())")
    }

    var addr = sockaddr_un()
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { dst in
      socketPath.withCString { src in
        _ = Darwin.memcpy(dst, src, min(socketPath.utf8.count + 1, 104))
      }
    }

    let bindResult = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
        Darwin.bind(fd, sptr, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bindResult == 0 else {
      Darwin.close(fd)
      throw XhammerError.socketError("bind() failed: \(Self.errnoString())")
    }

    guard Darwin.listen(fd, 10) == 0 else {
      Darwin.close(fd)
      throw XhammerError.socketError("listen() failed: \(Self.errnoString())")
    }

    // Owner-only permissions on the socket file
    Darwin.chmod(socketPath, 0o600)

    serverFD = fd
    logger.info("Listening on \(socketPath)")

    let handler = connectionHandler
    acceptTask = Task.detached { [fd, logger] in
      while !Task.isCancelled {
        let clientFD = await Self.acceptAsync(serverFD: fd)
        if Task.isCancelled { break }
        guard clientFD >= 0 else { continue }
        Task.detached {
          await handler(clientFD)
          Darwin.close(clientFD)
        }
      }
      logger.info("Accept loop exiting")
    }
  }

  func stop() {
    acceptTask?.cancel()
    acceptTask = nil
    if serverFD >= 0 {
      Darwin.close(serverFD)
      serverFD = -1
    }
  }

  // MARK: - Internals

  private static func acceptAsync(serverFD: Int32) async -> Int32 {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInteractive).async {
        var addr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFD = withUnsafeMutablePointer(to: &addr) { ptr in
          ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
            Darwin.accept(serverFD, sptr, &len)
          }
        }
        continuation.resume(returning: clientFD)
      }
    }
  }

  private static func errnoString() -> String {
    String(cString: Darwin.strerror(Darwin.errno))
  }
}

// MARK: - POSIX I/O helpers (free functions, used by DaemonServer)

/// Read a newline-terminated line from a file descriptor (blocking).
func readLine(fd: Int32) -> String? {
  var buffer = Data()
  var byte = [UInt8](repeating: 0, count: 1)
  while true {
    let n = Darwin.read(fd, &byte, 1)
    if n <= 0 { return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8) }
    if byte[0] == 0x0A { return String(data: buffer, encoding: .utf8) }
    buffer.append(byte[0])
  }
}

/// Write a string followed by a newline to a file descriptor.
@discardableResult
func writeLine(_ s: String, fd: Int32) -> Bool {
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
