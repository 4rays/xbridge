# Custom Daemonized Xcode CLI (Swift/SPM)

## Goal

Build a small, purpose-built CLI for Xcode's MCP bridge that:

- talks to `xcrun mcpbridge`
- keeps a single long-lived client identity
- uses a per-user daemon so Xcode permission can be granted once to that daemon-owned client

This is intentionally a narrow tool for Xcode, not a generic MCP framework.

## Why Build This

A custom tool can be:

- smaller
- easier to debug
- easier to distribute as a stable native binary
- more explicit about Xcode-specific commands and errors

## Decisions

- The project will target Swift as the primary implementation language.
- The build system will be Swift Package Manager.
- The system will be split into two executables: `xcode-tools` and `xcode-toolsd`.
- The daemon will own the only long-lived connection to `xcrun mcpbridge`.
- The CLI will talk only to the daemon over a local Unix domain socket.
- The daemon API will be a small app-specific RPC protocol, not raw MCP.
- V1 will focus on read/build/test flows and daemon lifecycle, not full Xcode tool coverage.

## Product Shape

The tool should consist of two binaries:

1. `xcode-tools`
   The user-facing CLI.

2. `xcode-toolsd`
   A per-user background daemon that owns a long-lived `xcrun mcpbridge` subprocess.

The daemon is the only process that should directly communicate with `xcrun mcpbridge`.

## Core Idea

The CLI should never talk to `xcrun mcpbridge` directly.

Instead:

```text
xcode-tools -> unix domain socket -> xcode-toolsd -> stdio -> xcrun mcpbridge -> Xcode
```

That gives us:

- one stable client identity from Xcode's point of view
- persistence across multiple CLI invocations
- a place to handle reconnects, logs, and health checks

## Scope

### V1

Ship only the essential workflow:

- `list-windows`
- `build <tab-id>`
- `test <tab-id>`
- `test-list <tab-id>`
- `read <file> <tab-id>`
- `grep <pattern> <tab-id> [path]`
- `issues <tab-id>`
- `build-log <tab-id>`
- `status`
- `stop`
- `restart`

### Deferred

Defer these until the daemon and permission model are proven:

- `write`
- `update`
- `rm`
- `mv`
- `mkdir`
- previews and snippet execution
- full dynamic tool discovery
- multi-user or remote access

## Non-Goals

- building a generic MCP client framework
- supporting arbitrary MCP servers beyond Xcode
- exposing the daemon over the network
- implementing collaborative or multi-user access
- optimizing for parallel tool execution in v1
- shipping full write/mutation coverage before the permission model is validated

## Recommended Implementation

Use Swift with Swift Package Manager.

Why Swift:

- native macOS binary with a stable process identity
- clean fit for `Process`, pipes, file APIs, and launchd integration
- straightforward future path for packaging and signing
- no external runtime dependency once built
- strong alignment with an Apple-platform-only tool

Go would also work well, but this version assumes we are explicitly choosing tighter Apple-native integration over lighter tooling.

## High-Level Architecture

### 1. CLI Layer

`xcode-tools` is responsible for:

- parsing commands
- connecting to the daemon socket
- auto-starting the daemon if missing
- sending local RPC requests
- formatting output for humans

It should not:

- speak MCP directly
- manage the bridge subprocess
- own reconnect logic beyond "start daemon if unavailable"

### 2. Daemon Layer

`xcode-toolsd` is responsible for:

- listening on a per-user Unix domain socket
- starting `xcrun mcpbridge`
- performing MCP initialization
- sending `tools/list` and `tools/call`
- caching known tool metadata
- restarting the bridge when it exits unexpectedly
- exposing health and lifecycle commands

### 3. Bridge Layer

The daemon should wrap the MCP bridge as a managed child process:

- executable: `xcrun`
- args: `mcpbridge`
- transport: stdio

The daemon should own:

- stdin writer
- stdout reader
- stderr log capture
- request/response correlation

## Local RPC Between CLI and Daemon

Do not expose raw MCP as the daemon API.

Use a tiny app-specific JSON protocol over a Unix socket.

Example requests:

```json
{"id":"1","method":"status"}
{"id":"2","method":"stop"}
{"id":"3","method":"restart"}
{"id":"4","method":"callTool","params":{"tool":"BuildProject","arguments":{"tabIdentifier":"windowtab1"}}}
```

Example responses:

```json
{"id":"1","ok":true,"result":{"daemon":"running","bridge":"healthy"}}
{"id":"4","ok":true,"result":{"content":[{"type":"text","text":"Build succeeded"}]}}
{"id":"4","ok":false,"error":{"message":"Xcode is not running"}}
```

This keeps the daemon API stable even if internal MCP details evolve.

## MCP Responsibilities Inside the Daemon

The daemon should implement a minimal MCP stdio client:

- send `initialize`
- optionally send `initialized`
- call `tools/list`
- call `tools/call`
- correlate responses by `id`

V1 does not need a complete generic MCP abstraction. It only needs enough to talk to the Xcode bridge reliably.

## Startup and Lifecycle

### First Run

1. User runs `xcode-tools list-windows`
2. CLI does not find the daemon socket
3. CLI starts `xcode-toolsd`
4. Daemon launches `xcrun mcpbridge`
5. Daemon initializes MCP
6. Xcode prompts for permission
7. User clicks Allow
8. Subsequent CLI calls reuse the same daemon-managed connection

### Normal Run

1. CLI connects to daemon
2. CLI sends request
3. Daemon forwards to the bridge
4. Daemon returns result

### Failure Recovery

If the bridge exits or becomes unresponsive:

1. daemon marks bridge unhealthy
2. daemon restarts `xcrun mcpbridge`
3. daemon re-initializes the MCP session
4. daemon retries the original request once when safe

If the daemon itself is gone:

1. CLI detects socket failure
2. CLI starts daemon again
3. CLI retries once

## Permission Model Assumption

The key product assumption is:

Xcode permission should stick to the daemon-owned client identity, not to each short-lived CLI invocation.

This must be validated early.

The entire project is worth doing only if this assumption holds reliably enough in real use.

## Open Questions

- Does Xcode reliably treat the daemon-owned client as a stable identity across multiple CLI invocations?
- Is explicit `tabIdentifier` enough for the first release, or is `MCP_XCODE_PID` support needed immediately?
- Should the daemon auto-start only on demand, or should the project also ship an optional `launchd` agent for always-on behavior?
- Should v1 support only human-readable CLI output, or also a machine-readable JSON mode?
- Should bridge retry behavior be limited to one retry globally, or vary by command type?
- How much tool metadata should the daemon cache after `tools/list`?

## State and Files

Recommended per-user paths:

```text
~/Library/Application Support/xcode-tools/
  daemon.sock
  daemon.pid
  daemon.log
  state.json
```

The daemon should ensure the directory exists and use user-only permissions.

## Logging

V1 logging should be simple:

- daemon stdout/stderr to `daemon.log`
- bridge stderr appended to `daemon.log`
- optional request summaries:
  - timestamp
  - tool name
  - elapsed time
  - success/failure

Avoid logging full file contents by default.

## Project Layout

Suggested SwiftPM layout:

```text
Package.swift
Sources/
  xcode-tools/
    main.swift
  xcode-toolsd/
    main.swift
  CLI/
    Commands.swift
    OutputFormatter.swift
  Daemon/
    DaemonServer.swift
    SocketServer.swift
    BridgeProcess.swift
    MCPClient.swift
    StateStore.swift
  Protocol/
    LocalRPC.swift
    MCPMessages.swift
    Errors.swift
  LogSupport/
    Logger.swift
Launchd/
  com.example.xcode-toolsd.plist
Tests/
  CLITests/
  DaemonTests/
  ProtocolTests/
```

## Key Modules

### `Daemon`

Responsibilities:

- launch `xcrun mcpbridge`
- manage stdin/stdout/stderr pipes
- detect child exit
- expose restart hooks
- coordinate daemon lifecycle and health

Likely files:

- `DaemonServer.swift`
- `BridgeProcess.swift`
- `SocketServer.swift`
- `StateStore.swift`

### `Protocol`

Responsibilities:

- encode JSON-RPC requests
- decode JSON-RPC responses
- map request ids to pending continuations or callbacks
- implement `initialize`, `tools/list`, and `tools/call`

Likely files:

- `LocalRPC.swift`
- `MCPMessages.swift`
- `Errors.swift`

### `CLI`

Responsibilities:

- map CLI verbs to Xcode tool names
- validate command arguments
- build local RPC requests
- present output in a stable human-friendly way

Likely files:

- `Commands.swift`
- `OutputFormatter.swift`

### `LogSupport`

Responsibilities:

- provide lightweight logging helpers
- keep daemon and bridge logging consistent
- avoid unnecessary dependencies in v1

## Concurrency Strategy

Keep v1 simple.

- accept multiple CLI clients
- serialize bridge calls through one actor or one dedicated request queue
- do not attempt parallel MCP calls initially

This avoids subtle ordering and correlation bugs while the core system is being proven.

## UX Principles

- errors should mention Xcode explicitly when relevant
- `list-windows` should be the default discovery path for `tabIdentifier`
- command help should be concise
- daemon commands should be obvious: `status`, `stop`, `restart`
- failures should be honest and nonzero

## Testing Plan

### Unit Tests

- local RPC encoding/decoding
- CLI argument parsing
- MCP request/response parsing
- bridge restart state transitions

### Integration Tests

Use a fake MCP stdio server first:

- daemon starts bridge
- multiple CLI calls reuse the same daemon-owned process
- daemon restarts bridge after forced exit
- CLI auto-starts daemon when socket is missing

### Manual Validation

With real Xcode:

1. enable Xcode MCP
2. start daemon
3. verify permission prompt appears once
4. run multiple CLI invocations
5. verify prompt does not reappear on each call
6. restart CLI but keep daemon alive
7. verify access still works

## Risks

### 1. Permission Stickiness

The main risk is that Xcode may not treat the daemon identity the way we expect.

This is the first thing to validate.

### 2. Bridge Stability

`xcrun mcpbridge` may hang, exit, or change behavior across Xcode releases.

The daemon must tolerate restarts.

### 3. Multiple Xcode Instances

V1 should avoid smart guessing.

Use `tabIdentifier` explicitly and add `MCP_XCODE_PID` support later if needed.

### 4. Tool Surface Drift

Apple may add or rename tools.

V1 should hardcode only the small set we depend on.

## Delivery Plan

### Milestone 1: Validate the Model

- build a tiny daemon
- connect to `xcrun mcpbridge`
- support `status` and `list-windows`
- confirm Xcode permission behavior

### Milestone 2: Useful Daily Tool

- add build, test, read, grep, issues
- add restart logic
- add logging

### Milestone 3: Polish

- launchd support
- better output formatting
- packaging and install story

## Rough Effort

- prototype: 1 day
- solid internal v1: 3 to 5 days
- polished distributable version: 1 to 2 weeks

## Recommendation

Proceed only if Milestone 1 confirms the permission model.

If that works, a custom daemonized CLI is a very reasonable standalone alternative for an Xcode-specific workflow.
