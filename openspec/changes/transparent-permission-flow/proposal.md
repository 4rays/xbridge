## Why

Agents using xbridge get `"Xcode MCP bridge is not running"` when Xcode hasn't granted permission yet, and `xbridge status` falsely reports `healthy` because the health check never actually calls Xcode. Both issues cause agents to fail or loop — approving the Xcode dialog does nothing because the bridge process has already died by the time the user clicks Allow.

## What Changes

- **BREAKING**: Remove `relink` from the xbridge skill — agents must never see it
- `ping()` replaced with a real Xcode tool probe (`XcodeListWindows`) instead of `tools/list`
- Daemon handles permission-denial death transparently: detects cause, respawns bridge, retries the original call, waits for user approval
- Tool calls that time out waiting for permission return a structured `WAITING_FOR_PERMISSION` response (not `bridgeNotRunning`)
- `relink` CLI command hidden from help output (kept for human debugging only)
- `xbridge status` gains a distinct `awaiting-permission` bridge state

## Capabilities

### New Capabilities

- `permission-flow`: Transparent first-grant handling — daemon detects denial-suspected bridge death, respawns, retries the original call, surfaces `WAITING_FOR_PERMISSION` if the 45s budget elapses
- `bridge-health`: Accurate liveness probe using a real Xcode tool call; exposes `LinkState` (down / linking / ready / awaiting-permission) to status

### Modified Capabilities

## Impact

- `Sources/xbridged/BridgeProcess.swift` — tag in-flight requests by method; compute `TerminationCause` on death
- `Sources/xbridged/MCPClient.swift` — replace `isInitialized`/`isRelinking` booleans with `LinkState`; add grant retry loop; replace 2s blind auto-restart
- `Sources/xbridged/DaemonServer.swift` — `handleStatus` uses new probe; `handleCallTool` maps permission failures to structured errors
- `Sources/XbridgeCore/LocalRPC.swift` — add `code: String?` to `LocalRPCError`
- `Sources/XbridgeCore/Errors.swift` — add `awaitingPermission`, `xcodeUnavailable`
- `Sources/xbridge/Commands.swift` — hide `relink` from help
- `Sources/xbridge/OutputFormatter.swift` — render new bridge states and hints
- `skills/xbridge/SKILL.md` — strip all relink/permission plumbing; add `WAITING_FOR_PERMISSION` handling instruction
