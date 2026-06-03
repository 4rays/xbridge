## ADDED Requirements

### Requirement: Transparent permission-grant recovery
The daemon SHALL detect when a `tools/call` causes `xcrun mcpbridge` to exit (denial-suspected death), respawn the bridge, and retry the original call — without surfacing bridge lifecycle details to the caller.

#### Scenario: Tool call succeeds after user approves Xcode dialog
- **WHEN** an agent calls any tool command and `mcpbridge` exits during that call
- **AND** the user clicks Allow in the Xcode permission dialog within 45 seconds
- **THEN** the daemon retries the call and returns the real tool result to the caller
- **AND** the caller receives no indication that a retry occurred

#### Scenario: Caller receives structured error if budget elapses
- **WHEN** an agent calls any tool command and `mcpbridge` exits during that call
- **AND** the user does not approve the Xcode dialog within 45 seconds
- **THEN** the daemon returns a `WAITING_FOR_PERMISSION` error with message: "Xcode is waiting for permission. Click Allow in the Xcode dialog, then re-run the command."

#### Scenario: Concurrent tool calls during permission wait are serialized
- **WHEN** multiple tool calls arrive while `state == .awaitingGrant`
- **THEN** only one recovery attempt runs at a time
- **AND** subsequent callers wait for the active recovery to complete before proceeding

### Requirement: Infra-death circuit breaker
The daemon SHALL stop retrying and return `XCODE_UNAVAILABLE` after 3 consecutive handshake failures, to distinguish a permission-pending state from Xcode being genuinely closed or MCP being disabled.

#### Scenario: Circuit breaker trips on repeated handshake failure
- **WHEN** `mcpbridge` fails during `initialize` or `tools/list` 3 times in a row
- **THEN** the daemon sets `state = .down` and returns `XCODE_UNAVAILABLE`
- **AND** no further automatic restart attempts are made until a new tool call arrives

#### Scenario: Bridge restarts on next incoming call after circuit break
- **WHEN** a new tool call arrives after the circuit breaker has tripped
- **THEN** the daemon attempts to start and initialize the bridge fresh

### Requirement: Demand-driven restart
The daemon SHALL only restart `mcpbridge` in response to an incoming tool call, not on a timer.

#### Scenario: No restart when no calls are in flight
- **WHEN** `mcpbridge` exits and no tool call is pending
- **THEN** the daemon does NOT immediately restart `mcpbridge`
- **AND** `state` transitions to `.down`

#### Scenario: Bridge starts on first incoming call
- **WHEN** a tool call arrives and `state == .down`
- **THEN** the daemon starts `mcpbridge`, runs the handshake, and proceeds with the call

### Requirement: `relink` hidden from agents
The `relink` CLI command SHALL be omitted from `xbridge --help` output and from the xbridge skill.

#### Scenario: Help output does not list relink
- **WHEN** a user or agent runs `xbridge --help`
- **THEN** `relink` does not appear in the command list

#### Scenario: relink still executable for human debugging
- **WHEN** a human explicitly runs `xbridge relink`
- **THEN** the command executes normally
