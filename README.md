# xhammer

A daemonized CLI for Xcode's MCP bridge. Keeps a single long-lived connection to `xcrun mcpbridge` so Xcode only prompts for permission once per daemon session.

```
xhammer → unix socket → xhammerd → stdio → xcrun mcpbridge → Xcode
```

## Install

```bash
make install
```

Installs `xhammer` and `xhammerd` to `~/.local/bin`. Requires Swift 6.3+ and Xcode 16+.

## Usage

```bash
xhammer list-windows                        # discover tab IDs
xhammer build windowtab1
xhammer test windowtab1
xhammer read MyFile.swift windowtab1
xhammer grep "TODO" windowtab1
xhammer docs "SwiftUI animations"
xhammer status
```

The daemon starts automatically on first use. To manage it manually:

```bash
xhammer status    # daemon and bridge health
xhammer restart   # restart the MCP bridge
xhammer stop      # shut down the daemon
```

## Commands

| Command | Description |
|---|---|
| `list-windows` | List open Xcode windows and tab IDs |
| `build <tab>` | Build the project |
| `test <tab>` | Run all tests |
| `test-run <tab> <target> <id>` | Run a specific test |
| `test-list <tab>` | List available tests |
| `read <file> <tab>` | Read a file |
| `write <tab> <path> <content>` | Create or overwrite a file |
| `update <tab> <path> <old> <new>` | Replace text in a file |
| `grep <pattern> <tab> [path]` | Search in the project |
| `ls <tab> <path>` | List files at a project path |
| `glob <tab> [pattern]` | Find files by wildcard pattern |
| `issues <tab>` | Show navigator issues |
| `refresh-issues <tab> <file>` | Refresh diagnostics for a file |
| `build-log <tab>` | Show the build log |
| `mkdir <tab> <path>` | Create a directory |
| `rm <tab> <path>` | Remove a file or directory |
| `mv <tab> <src> <dst>` | Move or rename a file |
| `exec <tab> <file> <purpose> <code>` | Execute a Swift code snippet |
| `preview <tab> <file> [index]` | Render a SwiftUI preview |
| `docs <query> [framework]` | Search Apple Developer Documentation |
| `tools` | List all MCP tools from the bridge |
| `tool-schema <name>` | Show input schema for a tool |
| `call <ToolName> [json]` | Call any tool with raw JSON arguments |

## How It Works

`xhammerd` owns the only connection to `xcrun mcpbridge`. It handles MCP initialization, tool discovery, and request correlation. The CLI connects to the daemon over a Unix domain socket at `~/Library/Application Support/xhammer/daemon.sock`.

Because the daemon process is stable across CLI invocations, Xcode only shows the permission prompt once per session.

## State Files

```
~/Library/Application Support/xhammer/
  daemon.sock   # Unix domain socket
  daemon.pid    # Daemon PID
  daemon.log    # Daemon and bridge logs
```
