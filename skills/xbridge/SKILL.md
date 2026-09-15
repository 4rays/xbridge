---
name: xbridge
description: "Use when working with Xcode projects — building, testing, reading files, searching code, or running SwiftUI previews. Triggers include: 'build Xcode project', 'run tests', 'xbridge', 'Xcode MCP', or any Xcode development task."
---

# xbridge Skill

This skill enables AI agents to interact with Xcode projects via the **xbridge CLI**.

> **Xcode must be running.** xbridge communicates with Xcode directly — if Xcode is not open with a project loaded, every command will fail. Before proceeding, confirm Xcode is running and a project is open. If it's not, open it:
>
> ```bash
> open -a Xcode          # opens Xcode without a project
> open MyApp.xcodeproj   # opens a specific project
> open MyApp.xcworkspace # opens a workspace
> ```
>
> Sometimes the Xcode app is not called Xcode.app, but rather a versioned name like Xcode-26.0.app. List all Xcode apps with:
>
> ```bash
> ls /Applications/Xcode*.app
> ```
>
> If the bridge shows as unhealthy, ensure Xcode is open with a project and MCP is enabled in **Xcode > Settings > Intelligence**.

## Setup

Run:

```bash
which xbridge
```

If found, verify the bridge is running:

```bash
xbridge status
```

If the output indicates the bridge is not running, tell the user:

> **The Xcode MCP bridge isn't running.** Open Xcode with your project first:
>
> ```bash
> open MyApp.xcodeproj   # or .xcworkspace
> ```
>
> Then check status again — the daemon auto-recovers the bridge once Xcode is running:
>
> ```bash
> xbridge status
> ```
>
> If the bridge shows as `awaiting-permission` or a command hangs on first contact, Xcode is showing **Allow “xbridge” to access Xcode?**. Click **Allow** via Accessibility — see [Remote Allow](#remote-allow-accessibility). Do not wait for a human unless that click fails.

If found and bridge is running, skip to [Using xbridge](#using-xbridge).

If not found, install it:

```bash
brew tap 4rays/tap
brew install xbridge
```

Confirm the install:

```bash
xbridge status
```

Enable Xcode MCP: open **Xcode > Settings** (⌘,) → **Intelligence** → enable **Xcode Tools** under Model Context Protocol.

Then open your project in Xcode and proceed to [Using xbridge](#using-xbridge).

## Using xbridge

### Prerequisites

- xbridge installed (`brew install xbridge` via the `4rays/tap` tap)
- Xcode running with a project open
- Xcode MCP enabled in **Xcode > Settings > Intelligence > Model Context Protocol**

### Workspaces

Xcode 27 tools operate on a workspace. Start with:

```bash
xbridge list-workspaces
```

This returns identifiers like `workspace1` or `workspace-0a3nvoDgQe`. When more than one workspace is open, pass `--workspace <id>` on every other command:

```bash
xbridge --workspace workspace1 build
xbridge build --workspace workspace1
```

If no workspace is open, open one first — that is also what triggers the Allow prompt:

```bash
xbridge open-workspace /path/to/MyApp.xcodeproj
```

Xcode 27’s Allow grant lasts **24 hours per agent and project**. There is no permanent option. After it expires, `open-workspace` again and click Allow.

### Timeouts

Build, test, and log commands can run for minutes on large projects. Always pass `--timeout` when calling these via `xbridge call`, or set a generous shell timeout. Start conservative and scale up:

| Project size                  | Suggested timeout |
| ----------------------------- | ----------------- |
| Small (toy/sample)            | 1 min             |
| Medium (single app)           | 5 min             |
| Large (monorepo/many targets) | 15+ min           |

Commands most likely to need a timeout: `build`, `run`, `test`, `test-run`, `build-log`, `refresh-issues`.

## Commands Reference

### Daemon & Status

| Command          | Description                   |
| ---------------- | ----------------------------- |
| `xbridge status` | Show daemon and bridge status |

### Discovery

| Command                           | Description                               |
| --------------------------------- | ----------------------------------------- |
| `xbridge tools`                   | List all MCP tools from Xcode             |
| `xbridge tool-schema <ToolName>`  | Show input schema for a tool              |
| `xbridge call <ToolName> [json]`  | Call any MCP tool with optional JSON args |
| `xbridge --workspace <id> …`      | Target a workspace when several are open  |
| `xbridge list-workspaces`         | List open Xcode workspaces                |
| `xbridge open-workspace <path>`   | Open a .xcworkspace or .xcodeproj         |
| `xbridge close-workspace <id>`    | Close a workspace by identifier           |
| `xbridge list-schemes`            | List schemes                              |
| `xbridge switch-scheme <name>`    | Make a scheme active                      |
| `xbridge list-destinations`       | List run destinations                     |
| `xbridge switch-destination <title>` | Make a run destination active          |
| `xbridge list-targets`            | List targets                              |
| `xbridge list-test-plans`         | List test plans for the active scheme     |
| `xbridge switch-test-plan <name>` | Make a test plan active                   |

### File Operations

| Command                                 | Description                   |
| --------------------------------------- | ----------------------------- |
| `xbridge read <file>`                   | Read a file                   |
| `xbridge write <path> <content>`        | Create or overwrite a file    |
| `xbridge update <path> <old> <new>`     | Replace text in a file        |
| `xbridge ls <path>`                     | List files at path            |
| `xbridge glob [pattern]`                | Find files matching a pattern |
| `xbridge grep <pattern> [path]`         | Search file contents          |
| `xbridge mkdir <path>`                  | Create a directory            |
| `xbridge rm <path>`                     | Remove a file or directory    |
| `xbridge mv <src> <dst>`                | Move or rename a file         |

### Build & Test

| Command                                      | Description                             |
| -------------------------------------------- | --------------------------------------- |
| `xbridge build`                              | Build the current scheme                |
| `xbridge run`                                | Build and run the current scheme        |
| `xbridge stop-run`                           | Stop the running app                    |
| `xbridge build-log`                          | Show the build log                      |
| `xbridge console`                            | Show console output from the latest launch |
| `xbridge test`                               | Run all tests                           |
| `xbridge test-list`                          | List available tests                    |
| `xbridge test-run <target> <identifier>`     | Run a specific test                     |
| `xbridge issues [severity]`                  | Show build issues (severity: `error`\|`warning`\|`remark`, default: `error`) |
| `xbridge refresh-issues <file>`              | Refresh compiler diagnostics for a file |
| `xbridge build-settings <target>`            | Show build settings for a target        |
| `xbridge debug <command>`                    | Send an lldb command                    |

### Advanced

| Command                                    | Description                  |
| ------------------------------------------ | ---------------------------- |
| `xbridge exec <file> <purpose> <code>`     | Execute a Swift code snippet |
| `xbridge preview <file> [index]`           | Render a SwiftUI preview     |
| `xbridge docs <query> [framework]`         | Search Apple Developer Documentation |

Specialized tools (device interaction, localization, crash reports, entitlements) have no dedicated subcommand. Use `xbridge call <ToolName> [json]`.

## Common Workflows

### Build a project

```bash
xbridge list-workspaces
# → workspace1  /path/to/Project.xcodeproj

xbridge --workspace workspace1 build
xbridge --workspace workspace1 build-log
```

### Run tests

```bash
xbridge --workspace workspace1 test-list
# Output truncates on large projects — full list written to path in `fullTestListPath` field
xbridge --workspace workspace1 test
# or a specific test — parentheses () required in identifier or test won't be found:
xbridge --workspace workspace1 test-run MyTarget 'MyTests/testSomething()'
```

### Edit a file

```bash
xbridge --workspace workspace1 update Sources/MyView.swift 'Text("Hello")' 'Text("Hello, World!")'
```

### Search code

```bash
xbridge --workspace workspace1 grep "someFunction" Sources/
```

### Get Xcode issues

```bash
xbridge --workspace workspace1 issues
# Lists errors only (default)

xbridge --workspace workspace1 issues warning
# Lists warnings and above

xbridge --workspace workspace1 issues remark
# Lists everything

# Refresh diagnostics for a specific file first if issues are stale.
# Path is relative to workspace root (ProjectName/Path/To/File.swift):
xbridge --workspace workspace1 refresh-issues MyApp/Sources/MyView.swift
xbridge --workspace workspace1 issues
```

### Search documentation

```bash
xbridge docs "SwiftUI List" SwiftUI
```

> **Note:** `docs` output can be large (30KB+). Use narrow, specific queries and pass a framework name to limit results.

## Troubleshooting

**xbridge not found**
Install with `brew tap 4rays/tap && brew install xbridge`.

**`xbridge status` shows bridge down or unhealthy**
Ensure Xcode is open with a project and MCP is enabled in **Xcode > Settings > Intelligence > Model Context Protocol**. The daemon auto-starts and retries on the next command.

**Command returns `WAITING_FOR_PERMISSION`**
Xcode is showing **Allow “xbridge” to access Xcode?**. Click **Allow** via Accessibility — see [Remote Allow](#remote-allow-accessibility) — then re-run the same command. The daemon retries automatically once permission is granted.

**Grant expired / “isn't approved to use Xcode's tools yet”**
Xcode 27’s Allow grant lasts 24 hours per agent and project. Run `xbridge open-workspace /path/to/MyApp.xcodeproj` again and click Allow. There is no permanent option.

**`workspaceIdentifier is required`**
More than one workspace is open. Pass `--workspace <id>` from `xbridge list-workspaces`.

**No workspaces from `xbridge list-workspaces`**
Xcode must be running with a project open. Run `xbridge open-workspace MyApp.xcodeproj` first.

**Xcode MCP not enabled**
Go to **Xcode > Settings > Intelligence > Model Context Protocol** and enable Xcode Tools.

**MCP permission denied**
In Xcode Settings, revoke the process entry under MCP. The next tool command will trigger a fresh permission dialog — click **Allow** via [Remote Allow](#remote-allow-accessibility).

## Project Context

Add an `AGENTS.md` or `CLAUDE.md` in your project root:

```markdown
# Project Context

## Build System

- iOS 18 SwiftUI project
- Main scheme: MyApp

## Testing

- Test scheme: MyAppTests

## Project Structure

- Sources in: Sources/
- Tests in: Tests/
```

## Remote Allow (Accessibility)

Xcode prompts **Allow “xbridge” to access Xcode?** on first `xbridged` contact each daemon session (path + PID). It is an Xcode `AXDialog`, not a system TCC sheet. xbridge will not click it for you.

If the host (Ghostty, Terminal, the agent app) has Accessibility enabled, click **Allow** instead of waiting for a human:

```applescript
tell application "System Events"
  tell process "Xcode"
    set frontmost to true
    repeat with w in windows
      if (subrole of w is "AXDialog") then
        try
          set dialogText to ""
          repeat with t in static texts of w
            set dialogText to dialogText & (value of t as text) & " "
          end repeat
          if dialogText contains "xbridge" and dialogText contains "access Xcode" then
            if exists button "Allow" of w then
              click button "Allow" of w
              return "clicked Allow"
            end if
          end if
        end try
      end if
    end repeat
  end tell
end tell
return "no Allow dialog"
```

Confirm with `xbridge status` (`bridge : healthy`). Retry the same script if the dialog is still up — do not click `Allow` on `window 1` without checking the static text.

**Do not** walk `entire contents` of the Xcode process — it hangs. Query `windows` / `buttons` / `static texts` only.

If AppleScript cannot see or click the dialog, the **hosting process** lacks Accessibility — Terminal, Ghostty, iTerm, the agent app, or whatever launched `osascript`. Ask the developer to enable it in **System Settings → Privacy & Security → Accessibility** for that app, then retry the click. Until that is granted, a human has to click **Allow** in Xcode.
