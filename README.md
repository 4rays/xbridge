# xbridge

A daemonized CLI that keeps a single long-lived connection to Xcode's MCP bridge and reuses the daemon's agent identity across commands.

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

If `xbridge` is already installed, `xbridge skill` prints the exact `SKILL.md` shipped with that version—no Xcode, daemon, or network required. A harness can read it directly instead of relying on a stale copied skill. Upgrade xbridge to obtain a newer bundled skill. To save a copy:

```bash
mkdir -p .agents/skills/xbridge
xbridge skill > .agents/skills/xbridge/SKILL.md
```

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
xbridge skill                               # print bundled agent instructions
```

`--workspace <id>` is required when more than one workspace is open. Omit it when only one project is loaded.

Xcode 27 manages agent and folder permissions separately. Unsigned agents can be approved for 24 hours; signed agents and folders also support durable approval with `--always`.

The daemon starts automatically on first use. Xcode may ask for permission the first time the daemon connects to the bridge.

Inspect native Xcode MCP permissions and pending requests without Accessibility access:

```bash
xbridge status                                  # native MCP status plus daemon/bridge health
xbridge status --fix                            # native status and human approval instructions
xbridge status --fix --project /path/to/project  # include the intended project root for review
xcrun mcp-server status --format json            # native status alone (no xbridge daemon)
```

`status --fix` is read-only: it does not click UI, invoke sudo, start the daemon, or grant access. It shows Apple's status JSON, including permissions, pending requests, and open workspaces. `--project` identifies the intended project for human review; it does not filter or approve requests. If no matching request is pending, run `xbridge open-workspace /path/to/MyApp.xcodeproj` first.

Verify each pending request's executable or folder path, then ask the human to run the matching command in their terminal with the actual request ID:

```bash
sudo xcrun mcp-server approve <request-id> --for-24-hours
```

Agent and folder requests may require separate approvals. Re-read status after each approval, then retry the original workspace operation to confirm access. Use `--always` only for a signed agent or folder when durable trust is intended; unsigned agents do not support it. Do not enable `--unsafe-always-allow-all-agents` to bypass approval. If using `--xcode-path`, select the same Xcode via `DEVELOPER_DIR` for manual `xcrun` commands.

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

Installs `xbridge` and `xbridged` to `~/.local/bin` and the bundled skill to `~/.local/share/xbridge`. Removes the obsolete `xbridge-allow` helper from that bin directory. Requires Swift 6.3+ and Xcode 27+ for native permission status.

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
| `run [--device <title>] [--debugger]`  | Build and run the current scheme      |
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

### Large Test Plans

`test-list` returns at most 100 tests inline. Its `fullTestListPath` artifact contains every test Xcode has discovered, and `test-run` can run a test outside the inline 100 when given its exact identifier. Swift Testing identifiers use `SuiteName/testName()` format, including the parentheses.

If both the response and artifact unexpectedly contain exactly 100 tests with `truncated: false`, Xcode's test discovery snapshot may be incomplete. Switch to the test target's owning scheme and list its tests, then switch back and list the original test plan again:

```bash
xbridge --workspace workspace1 switch-scheme Feature
xbridge --workspace workspace1 test-list
xbridge --workspace workspace1 switch-scheme App
xbridge --workspace workspace1 test-list
xbridge --workspace workspace1 test-run FeatureTests 'FeatureTests/testSomething()'
```

Running the test while its owning scheme is active is also a reliable fallback.

## How It Works

`xbridged` owns the only connection to Xcode's MCP bridge. It handles tool discovery and request correlation. The CLI connects to the daemon over a Unix domain socket at `~/Library/Application Support/xbridge/daemon.sock`.

Because the daemon process is stable across CLI invocations, commands reuse its granted agent permission until it expires or is revoked. Folder permissions are managed separately by Xcode.

## State Files

```
~/Library/Application Support/xbridge/
  daemon.sock   # Unix domain socket
  daemon.pid    # Daemon PID
  daemon.log    # Daemon and bridge logs
```
