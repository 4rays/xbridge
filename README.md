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

Xcode 27 asks you to Allow the agent the first time a project is opened via `open-workspace`. That grant lasts 24 hours per agent and project. There is no permanent option.

The daemon starts automatically on first use. Xcode may ask for permission the first time the daemon connects to the bridge.

For an Xcode 27 access prompt, run the repair from the **project root** (the directory shown in the dialog):

```bash
xbridge status                                  # read-only bridge health
xbridge status --fix                            # allow only if dialog path equals current directory
xbridge status --fix --project /path/to/project  # explicit project root from elsewhere
```

The underlying `xbridge-allow` helper is also available for inspection (`xbridge-allow`) or a guarded click (`xbridge-allow --allow /path/to/project`). From a source checkout, use `osascript scripts/allow-xcode-access.applescript [--allow /path/to/project]` instead.

Repair matches the `xbridge` prompt in **Xcode Service** (not the main Xcode process), requires its project path to match exactly, checks the dialog text and two-button layout, and refuses to click if the structure changes or more than one prompt matches. In the observed SwiftUI dialog the buttons expose no Accessibility labels; the **upper** button is “Allow for 24 Hours.” The terminal running the CLI needs macOS Accessibility permission. `status --fix` does not discover grants or create a prompt: first run the workspace operation that requests access. It rechecks global bridge health after clicking; retry the original workspace operation to confirm project access.

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

Installs `xbridge`, `xbridged`, and `xbridge-allow` to `~/.local/bin`. Requires Swift 6.3+ and Xcode 26+.

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
| `device-agent <key> <goal> [options]` | Preview or run a bounded Jev device workflow |
| `tools`                                | List all MCP tools from the bridge    |
| `tool-schema <name>`                   | Show input schema for a tool          |
| `call <ToolName> [json]`               | Call any tool with raw JSON arguments |

### Jev Device Agent

`device-agent` uses an existing Device Hub session. It never starts, installs, replaces, or ends a session. Preview is the default and sends no interaction command:

```bash
export TYPESAFE_API_KEY=...
export TYPESAFE_MODEL=jev-latest # optional

xbridge --workspace workspace1 device-start "Verify Search" "iPhone 18 Pro"
xbridge --workspace workspace1 device-install "Verify Search"

# One observation and one Jev decision; no mutation.
xbridge device-agent "Verify Search" "Open Search"

# Explicitly run the bounded observe/decide/freshness-check/execute loop.
xbridge device-agent "Verify Search" "Open Search and enter Kai" \
  --act --steps 8 --min-confidence 0.6 --text "Kai"

xbridge device-end "Verify Search"
```

Options:

- `--act` enables interaction. Without it, the command is preview-only.
- `--bundle-id <id>` supplies app identity/activation when Device Hub does not.
- `--steps <n>` caps executed actions; decision, stale-target, wait, and no-op guards also apply.
- `--min-confidence <0...1>` gates the operation and its consumed target; default `0.5`.
- Repeated `--text <value>` options add exact text candidates. Goal spans are also candidates. Jev selects a complete value but never generates text.
- `--trace <directory>` selects the run directory. The default is under `~/Library/Application Support/xbridge/device-agent-runs/`.

The accessibility hierarchy, goal, and exact text candidates are sent to TypeSafe as structured text. Screenshots, artifact paths, coordinates, credentials, secure-field contents, and raw commands are not sent. Secure fields are never offered for typing. Trace directories are owner-only and contain copied Device Hub artifacts plus normalized observations, redacted TypeSafe exchanges, decisions, actions, retries, timing, and the final status.

Terminal statuses include `preview`, `model_done`, `blocked`, `needs_input`, `low_confidence`, `stuck`, `unstable_ui`, `input_unverified`, `session_expired`, `ambiguous_mutation`, `step_limit`, `decision_limit`, `observation_failure`, and `invalid_policy_response`. `model_done` means Jev judged a fresh, unchanged UI complete; it is not independent verification.

Use a simulator first. If a session expires, start a new one explicitly and rerun the agent with its new key. For uncertain mutations, stale targets, or unverified text, inspect the trace and continue manually with `device-interact`; xbridge will not retry or substitute a session.

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

Because the daemon process is stable across CLI invocations, Xcode only shows the permission prompt once per session.

## State Files

```
~/Library/Application Support/xbridge/
  daemon.sock   # Unix domain socket
  daemon.pid    # Daemon PID
  daemon.log    # Daemon and bridge logs
```
