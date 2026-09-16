# xbridge TODO

## Milestone 1 — Validate the Permission Model

- [x] Test `list-workspaces` against a real running Xcode (validate MCP tool name)
- [ ] Verify Xcode prompts for permission once and sticks to the daemon identity
- [x] Confirm tool names returned by `xcrun mcpbridge` match `XcodeTool` constants in `MCPMessages.swift`

## Milestone 2 — Useful Daily Tool

- [ ] Bridge restart on unexpected exit (retry pending request once)
- [ ] Configurable request timeout (default 30s)
- [ ] `MCP_XCODE_PID` support for targeting a specific Xcode instance
- [ ] JSON output mode (`--json` flag) for scripting

## Milestone 3 — Polish

- [ ] launchd plist (`Launchd/com.kaishin.xbridged.plist`)
- [ ] Install script / Makefile
- [ ] `xbridge help <command>` detailed help
- [ ] Better stderr formatting (colors, structured errors)

## Deferred (per spec)

- `write`, `update`, `rm`, `mv`, `mkdir` — write/mutation tools
- Multi-user or remote socket access
- Full dynamic tool discovery
- Parallel MCP calls
