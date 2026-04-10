# xhammer

## Architecture

- `xhammer` — user-facing CLI; connects to daemon over Unix socket, auto-starts it if missing
- `xhammerd` — background daemon; owns the single long-lived `xcrun mcpbridge` connection
- `XhammerCore` — shared library (LocalRPC protocol, MCP messages, JSON types, paths)
- CLI↔daemon protocol: newline-delimited JSON (`LocalRPCRequest` / `LocalRPCResponse`)

## Build & Install

- `swift build` — debug build
- `swift build -c release` — release build
- `make install` — release build + install to `~/.local/bin` (no sudo needed)
- Binaries: `.build/debug/xhammer`, `.build/debug/xhammerd`
- `swift test` — run unit tests (XhammerCoreTests: LocalRPC, MCPMessages)

## Running

- Start daemon manually: `.build/debug/xhammerd &`
- After rebuilding xhammerd, run `xhammer stop` first — old daemon is still bound to the socket
- Daemon socket: `~/Library/Application Support/xhammer/daemon.sock`
- Daemon log: `~/Library/Application Support/xhammer/daemon.log`

## Xcode MCP Bridge

- Tool names are PascalCase: `XcodeListWindows`, `BuildProject`, `XcodeGrep`, etc.
- Run `xhammer tools` to see the live list from the bridge
- Run `xhammer tool-schema <name>` to inspect argument schemas
- Bridge response format: `{"structuredContent":{"message":"..."},"content":[...]}`
- `structuredContent.message` is plain text; `content[0].text` is JSON-encoded

## Swift Concurrency (Swift 6)

- All global state must be `Sendable`; `Command` closures need `@Sendable`
- `FileHandle` in structs needs `@unchecked Sendable`
- Non-Sendable types stored in actors need `nonisolated(unsafe)`
