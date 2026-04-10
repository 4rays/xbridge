import Foundation
import Testing
@testable import XhammerCore

@Suite("MCP message encoding and decoding")
struct MCPMessagesTests {
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  // MARK: - MCPRequest

  @Test("MCPRequest encodes correct JSON-RPC 2.0 structure")
  func mcpRequestEncoding() throws {
    let req = MCPRequest(id: 3, method: "tools/list")
    let data = try encoder.encode(req)
    let json = try decoder.decode([String: JSONValue].self, from: data)

    #expect(json["jsonrpc"] == .string("2.0"))
    #expect(json["id"] == .int(3))
    #expect(json["method"] == .string("tools/list"))
  }

  @Test("MCPRequest with params round-trips")
  func mcpRequestWithParams() throws {
    let params: JSONValue = ["protocolVersion": "2024-11-05"]
    let req = MCPRequest(id: 1, method: "initialize", params: params)
    let data = try encoder.encode(req)
    let decoded = try decoder.decode(MCPRequest.self, from: data)

    #expect(decoded.id == 1)
    #expect(decoded.method == "initialize")
    #expect(decoded.params?["protocolVersion"]?.stringValue == "2024-11-05")
  }

  // MARK: - MCPResponse

  @Test("Successful MCPResponse decodes result")
  func mcpSuccessResponse() throws {
    let json = #"{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}"#
    let resp = try decoder.decode(MCPResponse.self, from: Data(json.utf8))

    #expect(resp.id == 2)
    #expect(resp.isSuccess)
    #expect(resp.error == nil)
  }

  @Test("Error MCPResponse decodes error payload")
  func mcpErrorResponse() throws {
    let json = #"{"jsonrpc":"2.0","id":5,"error":{"code":-32601,"message":"Method not found"}}"#
    let resp = try decoder.decode(MCPResponse.self, from: Data(json.utf8))

    #expect(resp.id == 5)
    #expect(!resp.isSuccess)
    #expect(resp.error?.code == -32601)
    #expect(resp.error?.message == "Method not found")
  }

  // MARK: - JSONValue

  @Test("JSONValue decodes all primitive types")
  func jsonValuePrimitives() throws {
    let nullJSON = "null"
    let boolJSON = "true"
    let intJSON = "42"
    let doubleJSON = "3.14"
    let stringJSON = #""hello""#

    let null = try decoder.decode(JSONValue.self, from: Data(nullJSON.utf8))
    let bool = try decoder.decode(JSONValue.self, from: Data(boolJSON.utf8))
    let int = try decoder.decode(JSONValue.self, from: Data(intJSON.utf8))
    let double = try decoder.decode(JSONValue.self, from: Data(doubleJSON.utf8))
    let string = try decoder.decode(JSONValue.self, from: Data(stringJSON.utf8))

    #expect(null.isNull)
    #expect(bool.boolValue == true)
    #expect(int.intValue == 42)
    #expect(double.doubleValue == 3.14)
    #expect(string.stringValue == "hello")
  }

  @Test("JSONValue subscript access on object")
  func jsonValueSubscript() throws {
    let json = #"{"key":"value","nested":{"n":1}}"#
    let value = try decoder.decode(JSONValue.self, from: Data(json.utf8))

    #expect(value["key"]?.stringValue == "value")
    #expect(value["nested"]?["n"]?.intValue == 1)
    #expect(value["missing"] == nil)
  }

  @Test("JSONValue array subscript")
  func jsonValueArraySubscript() throws {
    let json = #"[10,20,30]"#
    let value = try decoder.decode(JSONValue.self, from: Data(json.utf8))

    #expect(value[0]?.intValue == 10)
    #expect(value[2]?.intValue == 30)
    #expect(value[5] == nil)
  }

  @Test("MCPInitializeParams encodes required fields")
  func initializeParamsEncoding() throws {
    let params = MCPInitializeParams()
    let data = try encoder.encode(params)
    let json = try decoder.decode([String: JSONValue].self, from: data)

    #expect(json["protocolVersion"]?.stringValue == "2024-11-05")
    #expect(json["clientInfo"]?["name"]?.stringValue == "xhammer")
  }
}
