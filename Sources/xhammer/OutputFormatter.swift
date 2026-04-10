import Foundation
import XhammerCore

/// Formats daemon responses for human-readable terminal output.
struct OutputFormatter {
  // MARK: - Top-level dispatch

  static func format(response: LocalRPCResponse, method: String) -> String {
    if !response.ok {
      let msg = response.error?.message ?? "Unknown error"
      return "error: \(msg)"
    }
    guard let result = response.result else {
      return "(no result)"
    }

    switch method {
    case LocalRPCMethod.status:
      return formatStatus(result)
    case LocalRPCMethod.stop, LocalRPCMethod.restart:
      return result["message"]?.stringValue ?? "ok"
    case LocalRPCMethod.callTool:
      return formatToolResult(result)
    default:
      return formatJSON(result)
    }
  }

  // MARK: - Formatters

  private static func formatStatus(_ result: JSONValue) -> String {
    let daemon = result["daemon"]?.stringValue ?? "?"
    let bridge = result["bridge"]?.stringValue ?? "?"
    let tools = result["tools"]?.intValue.map(String.init) ?? "?"
    return """
      daemon : \(daemon)
      bridge : \(bridge)
      tools  : \(tools)
      """
  }

  /// Extracts text content from an MCP tool call result.
  ///
  /// xcrun mcpbridge returns:
  ///   { "structuredContent": {"message": "<plain text>"},
  ///     "content": [{"type":"text","text":"{\"message\":\"<plain text>\"}"}] }
  ///
  /// We prefer `structuredContent.message` (plain text), then try to unwrap
  /// JSON-in-text from the content array, then fall back to raw JSON.
  static func formatToolResult(_ result: JSONValue) -> String {
    // 1. structuredContent.message (xcrun mcpbridge — plain text, fastest path)
    if let msg = result["structuredContent"]?["message"]?.stringValue, !msg.isEmpty {
      return msg
    }
    // 2. content array — standard MCP format or JSON-wrapped text
    if let data = try? JSONEncoder().encode(result),
      let callResult = try? JSONDecoder().decode(MCPToolCallResult.self, from: data)
    {
      let raw = callResult.content.compactMap(\.text).joined(separator: "\n")
      if !raw.isEmpty {
        // Unwrap JSON-wrapped text: {"message":"..."} or {"content":"..."}
        if let textData = raw.data(using: .utf8),
          let textJSON = try? JSONDecoder().decode(JSONValue.self, from: textData)
        {
          if let msg = textJSON["message"]?.stringValue { return msg }
          if let msg = textJSON["content"]?.stringValue { return msg }
        }
        return raw
      }
    }
    return formatJSON(result)
  }

  /// Pretty-prints a JSONValue.
  static func formatJSON(_ value: JSONValue) -> String {
    guard
      let data = try? JSONEncoder().encode(value),
      let str = String(data: data, encoding: .utf8)
    else { return "(unrepresentable)" }
    return str
  }
}
