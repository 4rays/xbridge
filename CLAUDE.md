# xbridge

## Architecture

- `xbridge` — user-facing CLI; connects to daemon over Unix socket, auto-starts it if missing
- `xbridged` — background daemon; owns the single long-lived `xcrun mcpbridge` connection
- `XbridgeCore` — shared library (LocalRPC protocol, MCP messages, JSON types, paths)
- CLI↔daemon protocol: newline-delimited JSON (`LocalRPCRequest` / `LocalRPCResponse`)

## Build & Install

- `swift build` — debug build
- `swift build -c release` — release build
- `make install` — release build + install to `~/.local/bin` (no sudo needed)
- Binaries: `.build/debug/xbridge`, `.build/debug/xbridged`
- `swift test` — run unit tests (XbridgeCoreTests: LocalRPC, MCPMessages)

## Running

- Start daemon manually: `.build/debug/xbridged &`
- After rebuilding xbridged, run `xbridge stop` first — old daemon is still bound to the socket
- Daemon socket: `~/Library/Application Support/xbridge/daemon.sock`
- Daemon log: `~/Library/Application Support/xbridge/daemon.log`

## Xcode MCP Bridge

- Tool names are PascalCase: `XcodeListWorkspaces`, `BuildProject`, `XcodeGrep`, etc.
- Xcode 27 dropped `tabIdentifier` / `XcodeListWindows`. Tools take an optional `workspaceIdentifier` (`xbridge --workspace <id> …`). Required when more than one workspace is open.
- First contact with a project is `XcodeOpenWorkspace`. Inspect agent/folder grants and pending requests with `xcrun mcp-server status --format json` (Xcode 27+). `xbridge status` includes this native status; `status --fix` prints it and human approval instructions without contacting the daemon.
- Approval is a human-run `sudo xcrun mcp-server approve <request-id> --for-24-hours`. Unsigned agents cannot use `--always`; signed agents and folders can. Never automate sudo or use Accessibility traversal to click approval. Verify executable/folder paths and re-read status after each approval.
- Health probe is `XcodeListWorkspaces` (no args, no side effects).
- Run `xbridge tools` to see the live list from the bridge
- Run `xbridge tool-schema <name>` to inspect argument schemas
- Bridge response format: `{"structuredContent":{"message":"..."},"content":[...]}`
- `structuredContent.message` is plain text; `content[0].text` is JSON-encoded

## Subcommand Policy

First-class subcommands cover daily Xcode 27 workflows (workspaces, schemes, destinations, build/run/test, files, device hub). Specialized tools (localization, crash reports, entitlements) stay on `xbridge call <ToolName> [json]`.

To check what tools the connected Xcode actually exposes: `xbridge tools`

## Swift Concurrency (Swift 6)

- All global state must be `Sendable`; `Command` closures need `@Sendable`
- `FileHandle` in structs needs `@unchecked Sendable`
- Non-Sendable types stored in actors need `nonisolated(unsafe)`
