## ADDED Requirements

### Requirement: Real Xcode liveness probe
`MCPClient.probe()` SHALL call `XcodeListWindows` (a real Xcode tool) to determine bridge health. `tools/list` MUST NOT be used as a health indicator.

#### Scenario: probe returns healthy when XcodeListWindows succeeds
- **WHEN** `probe()` is called and `XcodeListWindows` returns a non-error result
- **THEN** bridge state is reported as `healthy`

#### Scenario: probe returns awaiting-permission when bridge died during call
- **WHEN** `probe()` is called and `mcpbridge` exits during the `XcodeListWindows` call
- **THEN** bridge state is reported as `awaiting-permission`

#### Scenario: probe returns down when bridge is not running
- **WHEN** `probe()` is called and `mcpbridge` is not running
- **THEN** bridge state is reported as `down`

### Requirement: `LinkState` reflects actual Xcode reachability
`MCPClient` SHALL maintain a `LinkState` enum with values `down`, `linking`, `ready`, and `awaitingGrant`. `status` SHALL map these to the bridge field values `down`, `linking`, `healthy`, and `awaiting-permission` respectively.

#### Scenario: Status shows awaiting-permission with actionable hint
- **WHEN** `xbridge status` is called and `LinkState == .awaitingGrant`
- **THEN** output contains `bridge : awaiting-permission`
- **AND** output contains the hint: "Click Allow in the Xcode dialog"

#### Scenario: Status shows down with open-Xcode hint
- **WHEN** `xbridge status` is called and Xcode is not running
- **THEN** output contains `bridge : down`
- **AND** output contains the hint: "open Xcode first: open -a Xcode"

#### Scenario: Status shows healthy only when tool calls will succeed
- **WHEN** `xbridge status` is called and the `XcodeListWindows` probe succeeds
- **THEN** output contains `bridge : healthy`

### Requirement: Structured error codes on LocalRPCError
`LocalRPCError` SHALL include an optional `code: String?` field. Tool call failures SHALL populate `code` with `WAITING_FOR_PERMISSION`, `XCODE_UNAVAILABLE`, or `XCODE_ERROR` as appropriate.

#### Scenario: Permission error carries WAITING_FOR_PERMISSION code
- **WHEN** a tool call fails because permission budget elapsed
- **THEN** `LocalRPCError.code == "WAITING_FOR_PERMISSION"`
- **AND** `LocalRPCError.message` contains instructions to click Allow and re-run

#### Scenario: Infra error carries XCODE_UNAVAILABLE code
- **WHEN** a tool call fails because the circuit breaker tripped
- **THEN** `LocalRPCError.code == "XCODE_UNAVAILABLE"`
- **AND** `LocalRPCError.message` instructs the user to open Xcode with a project
