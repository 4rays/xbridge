# xbridge

A daemonized CLI that keeps a single long-lived connection to Xcode's MCP bridge, so Xcode only prompts for permission once per daemon session.

## Install

> [!TIP]
> The easiest way to install `xbridge` is by pointing your agent to this README. If you'd rather do it manually, follow the instructions below.

### Install the Bridge

```bash
brew tap 4rays/tap
brew install xbridge
```

`xbridge` requires Xcode MCP available. If `xbridge status` reports that the bridge cannot be found or started, update Xcode and Command Line Tools:

```bash
softwareupdate --all --install --force
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

> [!WARNING]
> In Xcode, enable MCP before using `xbridge`: open **Settings → Intelligence → Model Context Protocol** and turn it on.

### Install the Skill

#### Option 1: CLI Install (Recommended)

```bash
# Install all skills
npx skills add 4rays/xbridge

# Install specific skills
npx skills add 4rays/xbridge --skill xbridge

# List available skills
npx skills add 4rays/xbridge --list
```

This automatically installs to your `.agents/skills/` directory (and symlinks into `.claude/skills/` for Claude Code compatibility).

#### Option 2: Claude Code Plugin

```bash
# Add the marketplace
/plugin marketplace add 4rays/xbridge

# Install the plugin
/plugin install xbridge
```

Or load directly from a local path:

```bash
claude --plugin-dir /path/to/xbridge
```

> Claude Code specific. For other agents, use Option 1 or Option 3.

#### Option 3: Clone and Copy

```bash
git clone https://github.com/4rays/xbridge.git
cp -r xbridge/skills/* .agents/skills/
```

## Usage

```bash
xbridge list-windows                        # discover tab IDs
xbridge build windowtab1
xbridge test windowtab1
xbridge read MyFile.swift windowtab1
xbridge grep "TODO" windowtab1
xbridge docs "SwiftUI animations"
xbridge status
```

The daemon starts automatically on first use. Xcode may ask for permission the first time the daemon connects to the bridge.

To manage the daemon manually:

```bash
xbridge status    # daemon and bridge health
xbridge restart   # restart the MCP bridge
xbridge stop      # shut down the daemon
```

## Install from Source

```bash
make install
```

Installs `xbridge` and `xbridged` to `~/.local/bin`. Requires Swift 6.3+ and Xcode 26+.

## Commands

| Command                              | Description                           |
| ------------------------------------ | ------------------------------------- |
| `list-windows`                       | List open Xcode windows and tab IDs   |
| `build <tab>`                        | Build the project                     |
| `test <tab>`                         | Run all tests                         |
| `test-run <tab> <target> <id>`       | Run a specific test                   |
| `test-list <tab>`                    | List available tests                  |
| `read <file> <tab>`                  | Read a file                           |
| `write <tab> <path> <content>`       | Create or overwrite a file            |
| `update <tab> <path> <old> <new>`    | Replace text in a file                |
| `grep <pattern> <tab> [path]`        | Search in the project                 |
| `ls <tab> <path>`                    | List files at a project path          |
| `glob <tab> [pattern]`               | Find files by wildcard pattern        |
| `issues <tab>`                       | Show navigator issues                 |
| `refresh-issues <tab> <file>`        | Refresh diagnostics for a file        |
| `build-log <tab>`                    | Show the build log                    |
| `mkdir <tab> <path>`                 | Create a directory                    |
| `rm <tab> <path>`                    | Remove a file or directory            |
| `mv <tab> <src> <dst>`               | Move or rename a file                 |
| `exec <tab> <file> <purpose> <code>` | Execute a Swift code snippet          |
| `preview <tab> <file> [index]`       | Render a SwiftUI preview              |
| `docs <query> [framework]`           | Search Apple Developer Documentation  |
| `tools`                              | List all MCP tools from the bridge    |
| `tool-schema <name>`                 | Show input schema for a tool          |
| `call <ToolName> [json]`             | Call any tool with raw JSON arguments |

## How It Works

`xbridged` owns the only connection to Xcode's MCP bridge. It handles tool discovery and request correlation. The CLI connects to the daemon over a Unix domain socket at `~/Library/Application Support/xbridge/daemon.sock`.

Because the daemon process is stable across CLI invocations, Xcode only shows the permission prompt once per session.

## State Files

```
~/Library/Application Support/xbridge/
  daemon.sock   # Unix domain socket
  daemon.pid    # Daemon PID
  daemon.log    # Daemon and bridge logs
```
