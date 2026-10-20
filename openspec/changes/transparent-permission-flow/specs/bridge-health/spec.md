## ADDED Requirements

### Requirement: Real Xcode liveness probe
`MCPClient.probe()` SHALL call `XcodeListWorkspaces` (a real Xcode tool) to determine bridge health. `tools/list` MUST NOT be used as a health indicator.

#### Scenario: probe returns healthy when XcodeListWorkspaces succeeds
- **WHEN** `probe()` is called and `XcodeListWorkspaces` returns a non-error result
- **THEN** bridge state is reported as `healthy`

#### Scenario: probe returns awaiting-permission when bridge died during call
- **WHEN** `probe()` is called and `mcpbridge` exits during the `XcodeListWorkspaces` call
- **THEN** bridge state is reported as `awaiting-permission`

#### Scenario: probe returns down when bridge is not running
- **WHEN** `probe()` is called and `mcpbridge` is not running
- **THEN** bridge state is reported as `down`

### Requirement: `LinkState` reflects actual Xcode reachability
`MCPClient` SHALL maintain a `LinkState` enum with values `down`, `linking`, `ready`, and `awaitingGrant`. `status` SHALL map these to the bridge field values `down`, `linking`, `healthy`, and `awaiting-permission` respectively.

#### Scenario: Status shows awaiting-permission with actionable hint
- **WHEN** `xbridge status` is called and `LinkState == .awaitingGrant`
- **THEN** output contains `bridge : awaiting-permission`
- **AND** output directs the caller to `xbridge status --fix` for native permission status and human approval instructions

#### Scenario: Status shows down with native-server hint
- **WHEN** `xbridge status` is called and the MCP bridge is down
- **THEN** output contains `bridge : down`
- **AND** output directs the caller to inspect native server status and ensure MCP is enabled with a project open
- **AND** a closed Xcode GUI alone does not override bridge health, because the server can run headless

#### Scenario: Status shows healthy only when tool calls will succeed
- **WHEN** `xbridge status` is called and the `XcodeListWorkspaces` probe succeeds
- **THEN** output contains `bridge : healthy`

### Requirement: Structured error codes on LocalRPCError
`LocalRPCError` SHALL include an optional `code: String?` field. Tool call failures SHALL populate `code` with `WAITING_FOR_PERMISSION`, `XCODE_UNAVAILABLE`, or `XCODE_ERROR` as appropriate.

#### Scenario: Permission error carries WAITING_FOR_PERMISSION code
- **WHEN** a tool call fails because permission budget elapsed
- **THEN** `LocalRPCError.code == "WAITING_FOR_PERMISSION"`
- **AND** `LocalRPCError.message` directs the caller to `xbridge status --fix`, human approval in a terminal, and re-running the original command

#### Scenario: Infra error carries XCODE_UNAVAILABLE code
- **WHEN** a tool call fails because the circuit breaker tripped
- **THEN** `LocalRPCError.code == "XCODE_UNAVAILABLE"`
- **AND** `LocalRPCError.message` instructs the user to open Xcode with a project

### Requirement: Native permission discovery
`xbridge status` SHALL include the output of `xcrun mcp-server status --format json` on Xcode 27+. `status --fix [--project <path>]` SHALL show native status and human approval instructions without contacting the daemon or changing permissions. An explicit Xcode selection SHALL also apply to native status.

#### Scenario: Human approval replaces Accessibility repair
- **WHEN** `xbridge status --fix` is called
- **THEN** native permission and pending-request information is shown
- **AND** instructions tell the human to verify executable and folder paths and run `sudo xcrun mcp-server approve <request-id> --for-24-hours` for each matching pending request
- **AND** the CLI does not invoke sudo or Accessibility automation
- **AND** `--project` provides review context, not request filtering or automatic approval
- **AND** instructions explain that `--always` supports signed agents and folders, but not unsigned agents
