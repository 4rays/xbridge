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
xbridge list-workspaces                     # discover workspace IDs
xbridge --workspace workspace1 build
xbridge --workspace workspace1 test
xbridge --workspace workspace1 read MyFile.swift
xbridge --workspace workspace1 grep "TODO"
xbridge --workspace workspace1 list-schemes
xbridge status
```

`--workspace <id>` is required when more than one workspace is open. Omit it when only one project is loaded.

Xcode 27 asks you to Allow the agent the first time a project is opened via `open-workspace`. That grant lasts 24 hours per agent and project. There is no permanent option.

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

| Command                                | Description                           |
| -------------------------------------- | ------------------------------------- |
| `--workspace <id>`                     | Target a workspace (global flag)      |
| `list-workspaces`                      | List open Xcode workspaces            |
| `open-workspace <path>`                | Open a .xcworkspace or .xcodeproj     |
| `close-workspace <id>`                 | Close a workspace by identifier       |
| `list-schemes`                         | List schemes in the current workspace |
| `switch-scheme <name>`                 | Make a scheme active                  |
| `list-destinations`                    | List run destinations                 |
| `switch-destination <title>`           | Make a run destination active         |
| `list-targets`                         | List targets in the current workspace |
| `list-test-plans`                      | List test plans for the active scheme |
| `switch-test-plan <name>`              | Make a test plan active               |
| `build`                                | Build the current scheme              |
| `run`                                  | Build and run the current scheme      |
| `stop-run`                             | Stop the running app                  |
| `test`                                 | Run all tests                         |
| `test-run <target> <id>`               | Run a specific test                   |
| `test-list`                            | List available tests                  |
| `read <file>`                          | Read a file                           |
| `write <path> <content>`               | Create or overwrite a file            |
| `update <path> <old> <new>`            | Replace text in a file                |
| `grep <pattern> [path]`                | Search in the project                 |
| `ls <path>`                            | List files at a project path          |
| `glob [pattern]`                       | Find files by wildcard pattern        |
| `issues [severity]`                    | Show build issues                     |
| `refresh-issues <file>`                | Refresh diagnostics for a file        |
| `build-log`                            | Show the build log                    |
| `console`                              | Show console output from latest launch|
| `debug <command>`                      | Send an lldb command                  |
| `build-settings <target>`              | Show build settings for a target      |
| `mkdir <path>`                         | Create a directory                    |
| `rm <path>`                            | Remove a file or directory            |
| `mv <src> <dst>`                       | Move or rename a file                 |
| `exec <file> <purpose> <code>`         | Execute a Swift code snippet          |
| `preview <file> [index]`               | Render a SwiftUI preview              |
| `docs <query> [framework]`             | Search Apple Developer Documentation  |
| `device-start <session> [device]`      | Start a workspace-bound device session|
| `device-session <device> <session>`    | Start a device session without a workspace |
| `device-end <key>`                     | End a device session                  |
| `device-install <key>`                 | Build, install, and run on the session device |
| `device-interact <key> [command] [bundle-id]` | Synthesize a device event      |
| `tools`                                | List all MCP tools from the bridge    |
| `tool-schema <name>`                   | Show input schema for a tool          |
| `call <ToolName> [json]`               | Call any tool with raw JSON arguments |

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
