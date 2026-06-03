## 1. Core Types

- [x] 1.1 Add `TerminationCause` enum to `BridgeProcess` (`duringToolCall`, `duringHandshake`, `idle`)
- [x] 1.2 Add `LinkState` enum to `MCPClient` (`down`, `linking`, `ready`, `awaitingGrant`)
- [x] 1.3 Add `code: String?` to `LocalRPCError` in `LocalRPC.swift`
- [x] 1.4 Add `awaitingPermission` and `xcodeUnavailable` cases to `XbridgeError`

## 2. BridgeProcess Changes

- [x] 2.1 Tag each entry in `pendingResponses` with its MCP method name
- [x] 2.2 Compute `TerminationCause` in `handleTermination` based on in-flight request methods
- [x] 2.3 Expose `terminationCause: TerminationCause?` so `MCPClient` can read it after death

## 3. MCPClient Redesign

- [x] 3.1 Replace `isInitialized: Bool` and `isRelinking: Bool` with `linkState: LinkState`
- [x] 3.2 Remove `startHealthMonitor` (2s blind auto-restart)
- [x] 3.3 Implement `ensureReady()` — starts bridge and runs handshake if `state == .down`
- [x] 3.4 Implement grant retry loop in `callTool`: detect `duringToolCall` death, respawn, retry with backoff (`1s, 2s, 4s, 8s…`), 45s total budget
- [x] 3.5 Implement infra-death circuit breaker: 3 consecutive `duringHandshake` failures → `state = .down`, throw `xcodeUnavailable`
- [x] 3.6 Replace `ping()` with `probe()` — calls `XcodeListWindows`, returns `LinkState`
- [x] 3.7 Remove public `relink()` method (keep internal `respawnAndHandshake()` used by retry loop)

## 4. DaemonServer Changes

- [x] 4.1 Update `handleStatus` to call `probe()` and map `LinkState` to bridge field values
- [x] 4.2 Update `handleCallTool` to return structured `WAITING_FOR_PERMISSION` / `XCODE_UNAVAILABLE` errors with `code` field
- [x] 4.3 Remove `handleRelink` handler (or keep wired to internal `respawnAndHandshake` for human debug use)

## 5. CLI Changes

- [x] 5.1 Omit `relink` from `Commands.printHelp()` output
- [x] 5.2 Update `OutputFormatter.formatStatus` to render `awaiting-permission` and `down` states with correct hints
- [x] 5.3 Update CLI error rendering to surface `LocalRPCError.code` in messages

## 6. Skill Update

- [x] 6.1 Remove `relink` from Daemon & Status commands table in `skills/xbridge/SKILL.md`
- [x] 6.2 Remove all `xbridge relink` instructions from Setup and Troubleshooting sections
- [x] 6.3 Add `WAITING_FOR_PERMISSION` handling instruction: surface message to user verbatim, wait for confirmation, re-run command

## 7. Validation

- [ ] 7.1 `make install` and verify `xbridge status` shows `awaiting-permission` when Xcode permission not yet granted
- [ ] 7.2 Verify tool call blocks, user approves dialog, call completes transparently
- [ ] 7.3 Verify `xbridge status` shows `healthy` only after a real `XcodeListWindows` probe succeeds
- [ ] 7.4 Verify `xbridge --help` does not list `relink`
- [ ] 7.5 Verify `xbridge relink` still works when called explicitly
