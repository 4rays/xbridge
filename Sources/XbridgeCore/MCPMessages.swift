import Foundation

// MCP JSON-RPC 2.0 messages for communicating with xcrun mcpbridge over stdio.

// MARK: - Request / Response

public struct MCPRequest: Codable, Sendable {
  public let jsonrpc: String
  public let id: Int
  public let method: String
  public let params: JSONValue?

  public init(id: Int, method: String, params: JSONValue? = nil) {
    self.jsonrpc = "2.0"
    self.id = id
    self.method = method
    self.params = params
  }
}

public struct MCPResponse: Codable, Sendable {
  public let jsonrpc: String
  public let id: Int?
  public let result: JSONValue?
  public let error: MCPErrorPayload?

  public var isSuccess: Bool { error == nil }
}

public struct MCPNotification: Codable, Sendable {
  public let jsonrpc: String
  public let method: String
  public let params: JSONValue?

  public init(method: String, params: JSONValue? = nil) {
    self.jsonrpc = "2.0"
    self.method = method
    self.params = params
  }
}

public struct MCPErrorPayload: Codable, Sendable {
  public let code: Int
  public let message: String
  public let data: JSONValue?
}

// MARK: - initialize

public struct MCPInitializeParams: Codable, Sendable {
  public let protocolVersion: String
  public let capabilities: MCPClientCapabilities
  public let clientInfo: MCPClientInfo

  public init() {
    self.protocolVersion = "2024-11-05"
    self.capabilities = MCPClientCapabilities()
    self.clientInfo = MCPClientInfo(name: "xbridge", version: "1.0.0")
  }
}

public struct MCPClientCapabilities: Codable, Sendable {
  public init() {}
}

public struct MCPClientInfo: Codable, Sendable {
  public let name: String
  public let version: String

  public init(name: String, version: String) {
    self.name = name
    self.version = version
  }
}

// MARK: - tools/list

public struct MCPToolsListResult: Codable, Sendable {
  public let tools: [MCPTool]
}

public struct MCPTool: Codable, Sendable {
  public let name: String
  public let description: String?
  public let inputSchema: JSONValue?
}

// MARK: - tools/call

public struct MCPToolCallResult: Codable, Sendable {
  public let content: [MCPContent]
  public let isError: Bool?
}

public struct MCPContent: Codable, Sendable {
  public let type: String
  public let text: String?
}

// MARK: - Known Xcode tool names
//
// Discovered from xcrun mcpbridge via tools/list (Xcode 27).

public enum XcodeTool {
  // Workspace / project
  public static let listWorkspaces = "XcodeListWorkspaces"
  public static let openWorkspace = "XcodeOpenWorkspace"
  public static let closeWorkspace = "XcodeCloseWorkspace"
  public static let newProject = "XcodeNewProject"
  public static let newTarget = "XcodeNewTarget"
  public static let listTemplates = "XcodeListTemplates"
  public static let listTargets = "XcodeListTargets"
  public static let listSchemes = "XcodeListSchemes"
  public static let switchScheme = "XcodeSwitchScheme"
  public static let listRunDestinations = "XcodeListRunDestinations"
  public static let switchRunDestination = "XcodeSwitchRunDestination"
  public static let listTestPlans = "XcodeListTestPlans"
  public static let switchTestPlan = "XcodeSwitchTestPlan"

  // Build / run / test
  public static let buildProject = "BuildProject"
  public static let runProject = "RunProject"
  public static let stopProject = "StopProject"
  public static let runAllTests = "RunAllTests"
  public static let runSomeTests = "RunSomeTests"
  public static let listTests = "GetTestList"
  public static let getBuildLog = "GetBuildLog"
  public static let getConsoleOutput = "GetConsoleOutput"
  public static let invokeDebuggerCommand = "InvokeDebuggerCommand"

  // Files
  public static let readFile = "XcodeRead"
  public static let writeFile = "XcodeWrite"
  public static let updateFile = "XcodeUpdate"
  public static let removeFile = "XcodeRM"
  public static let makeDir = "XcodeMakeDir"
  public static let moveFile = "XcodeMV"
  public static let globFiles = "XcodeGlob"
  public static let grepInProject = "XcodeGrep"
  public static let listFiles = "XcodeLS"
  public static let refreshIssues = "XcodeRefreshCodeIssuesInFile"

  // Preview / snippet
  public static let renderPreview = "RenderPreview"
  public static let runCodeSnippet = "RunCodeSnippet"
  public static let documentationSearch = "DocumentationSearch"

  // Project settings
  public static let getTargetBuildSettings = "GetTargetBuildSettings"
  public static let updateTargetBuildSetting = "UpdateTargetBuildSetting"
  public static let getFileCompilerFlags = "GetFileCompilerFlags"
  public static let updateFileCompilerFlags = "UpdateFileCompilerFlags"
  public static let addEntitlement = "AddEntitlement"
  public static let addInfoPlist = "AddInfoPlist"

  // Device interaction
  public static let deviceInteractionStartSession = "DeviceInteractionStartSession"
  public static let deviceInteractionStartWorkspaceSession = "DeviceInteractionStartWorkspaceSession"
  public static let deviceInteractionEndSession = "DeviceInteractionEndSession"
  public static let deviceInteractionInstallAndRun = "DeviceInteractionInstallAndRun"
  public static let deviceInteractionSynthesize = "DeviceInteractionSynthesize"

  // Localization
  public static let localizationPlanner = "LocalizationPlanner"
  public static let stringCatalogRead = "StringCatalogRead"
  public static let stringCatalogContext = "StringCatalogContext"
  public static let stringCatalogEdit = "StringCatalogEdit"

  // Diagnostics (App Store Connect)
  public static let getTopCrashIssues = "GetTopCrashIssues"
  public static let getCrashIssueLogs = "GetCrashIssueLogs"
  public static let getTopFieldPerformanceIssues = "GetTopFieldPerformanceIssues"
  public static let getFieldPerformanceIssueLogs = "GetFieldPerformanceIssueLogs"
}
