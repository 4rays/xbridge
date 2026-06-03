## Context

`xbridged` owns a long-lived `xcrun mcpbridge` child process. When Xcode has not yet granted MCP permission, any `tools/call` causes `mcpbridge` to exit. The daemon's auto-recovery blindly restarts after 2s regardless of cause, creating a restart loop. The CLI surfaces the process death as `"Xcode MCP bridge is not running"` — correct technically, useless to the caller.

`ping()` in `MCPClient` sends `tools/list`, which `mcpbridge` answers from its own cached state without touching Xcode. This is why `status` shows `healthy` while real tool calls die.

`relink` was introduced as a user-facing recovery command, but agents shouldn't know about internal plumbing. The fix must be transparent.

## Goals / Non-Goals

**Goals:**
- Transparent permission-grant recovery: a tool call that triggers a permission dialog retries automatically until the user approves or a 45s budget elapses
- Accurate status: `status` calls a real Xcode tool; `bridge` field reflects actual Xcode reachability
- Agents see either a result or a single structured `WAITING_FOR_PERMISSION` message — nothing else

**Non-Goals:**
- Programmatically clicking Allow or reading TCC database
- Changing LocalRPC transport or MCP wire protocol
- Supporting Xcode versions before MCP was introduced

## Decisions

### 1. Explicit `LinkState` over boolean flags

Replace `isInitialized: Bool` + `isRelinking: Bool` with a single `LinkState` enum:

```swift
enum LinkState: Sendable {
  case down            // no live process
  case linking         // handshake in flight
  case ready           // last real probe succeeded
  case awaitingGrant   // denial-suspected death; retry loop active
}
```

**Why**: two booleans can express invalid combinations (`isInitialized: true, isRelinking: true`). A state machine makes invalid states unrepresentable and makes status reporting unambiguous.

### 2. `TerminationCause` for distinguishing denial from infra death

Tag each pending request with its method in `BridgeProcess`. On `handleTermination`, compute:

```swift
enum TerminationCause: Sendable {
  case duringToolCall   // denial-suspected
  case duringHandshake  // infra
  case idle             // Xcode quit or bridge crashed with nothing in flight
}
```

**Why**: we cannot read an exit code that reliably says "denied". Dying while a `tools/call` was in flight — after a successful handshake — is the only observable signal. Any other death is infrastructure and should not trigger the permission-wait loop.

**Alternative considered**: pattern-match stderr output from `mcpbridge`. Rejected — Apple can change the output format; process death is the stable signal.

### 3. Demand-driven restart, not timer-driven

Remove the 2s blind auto-restart in `startHealthMonitor`. Restart is triggered by an incoming tool call finding `state == .down` or transitioning to `awaitingGrant`. The health monitor task is removed entirely.

**Why**: blind restart creates the loop. Demand-driven restart means: no tool call = no restart = no new permission dialog spam.

### 4. Retry loop owns the original call

When a `tools/call` dies `duringToolCall`, the daemon does not return immediately. It respawns the bridge, re-runs the handshake, and retries the **same** call. The CLI blocks on the socket up to 60s.

Backoff between attempts: `1s, 2s, 4s, 8s, 8s…` capped at 8s, total budget 45s.

**Why**: if we return immediately after respawn, the agent (or human) has to re-issue the command. Making the retry transparent means: one call in, one result out, even if the first attempt triggered the dialog. The user sees the Xcode dialog, clicks Allow, and the blocked call completes.

**Alternative considered**: return `WAITING_FOR_PERMISSION` immediately and let the caller retry. Rejected — agents would need to implement retry logic, and the skill would need to document it. Transparent is better.

### 5. Circuit breaker for infra deaths

If respawn+handshake fails `duringHandshake` 3 times consecutively, set `state = .down` and return `XCODE_UNAVAILABLE`. Stop retrying.

**Why**: distinguishes "permission not yet granted" (transient, user-resolvable) from "Xcode closed / MCP disabled" (infra, no amount of retrying helps).

### 6. `XcodeListWindows` as the health probe

Replace `tools/list` with a real `XcodeListWindows` call in `MCPClient.probe()`.

**Why**: `tools/list` is answered by `mcpbridge` itself and does not exercise Xcode at all. `XcodeListWindows` requires a live Xcode connection, takes no arguments, has no side effects, and is already the mandatory first call in every agent workflow.

**Risk**: if Xcode is running but has no project open, `XcodeListWindows` may return an empty list without error — still counts as `healthy`, which is correct (the bridge works, there's just nothing to list).

### 7. Structured error codes on `LocalRPCError`

Add `code: String?` to `LocalRPCError`. Values: `WAITING_FOR_PERMISSION`, `XCODE_UNAVAILABLE`, `XCODE_ERROR`.

**Why**: lets the CLI and agents branch on error type without string-matching the message, which can change.

## Risks / Trade-offs

- **45s blocking call**: a tool call that triggers the permission dialog will block the CLI for up to 45s if the user doesn't click Allow. This is intentional — but long-running agents may time out on their end. Mitigated by surfacing `WAITING_FOR_PERMISSION` at budget expiry so callers know what happened.
- **`mcpbridge` may not always die on denial**: some Xcode versions might return an MCP error instead of exiting. If that happens, the `duringToolCall` heuristic won't fire and the error will surface as `XCODE_ERROR`. The user will still see a useful message; they just won't get auto-retry. Can be addressed later by also checking error content for "permission"/"denied" strings.
- **`XcodeListWindows` probe on `status`**: `status` now makes a real Xcode call. Cost is one round-trip (~100–500ms). Acceptable for an on-demand command; do not run on a timer.
- **`relink` hidden but not removed**: the CLI command remains for human debugging. If an agent discovers it through help output inspection, it could still call it. Mitigated by omitting it from `printHelp()`.

## Migration Plan

1. All changes are internal to the daemon and CLI — no LocalRPC wire format changes except adding optional `code` field (backwards-compatible).
2. No data migration needed.
3. Rollback: `brew install xbridge@<previous>` or `make install` from previous tag.

## Open Questions

1. Does `mcpbridge` always die on permission denial, or does behavior vary across Xcode versions? Needs validation against Xcode 16.x and 26.x once the loop is implemented.
2. Does Xcode grant permission per-path (persistent across restarts) or per-session? If per-session, `awaitingGrant` may recur after every daemon restart — the loop handles it, but the UX should be validated.
