---
name: xbridge
description: "Use when working with Xcode projects — building, testing, reading files, searching code, running SwiftUI previews, or driving a simulator. Triggers include: 'build Xcode project', 'run tests', 'xbridge', 'Xcode MCP', 'simulator', 'device hub', 'sim-bridge', or any Xcode development task."
---

# xbridge Skill

This skill enables AI agents to interact with Xcode projects via the **xbridge CLI**.

> **An Xcode MCP server must be available for project commands.** On Xcode 27+, `xcrun mcp-server status --format json` reports the server, permissions, pending requests, and open workspaces without Accessibility traversal. `xbridge status` includes this native status. `xbridge status --fix` reads it without contacting the daemon and prints approval instructions; it does not grant access or run sudo. The GUI need not be open if headless mode is already enabled. Otherwise, open Xcode with the project:
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
> If the bridge shows as unhealthy, inspect native status first. For GUI use, ensure Xcode is open with a project and MCP is enabled in **Xcode > Settings > Intelligence**.

## Setup

If `xbridge` is installed, `xbridge skill` prints the skill bundled with that installed version. A harness can read this output instead of an older saved copy; it does not need Xcode or the daemon. Upgrade xbridge to update the bundled skill.

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
If the bridge shows as `awaiting-permission`, a command returns `WAITING_FOR_PERMISSION`, or first contact hangs, use [Native permission approval](#native-permission-approval). Give the human the exact approval command for each verified pending request and wait for confirmation. Do not traverse Accessibility or click an Allow button.

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
- Xcode 27+ MCP server available, with the intended project open
- Xcode MCP enabled in **Xcode > Settings > Intelligence > Model Context Protocol**, or headless mode already enabled

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

Agent and folder permissions are separate. Unsigned agents can be approved for **24 hours**; signed agents and folders also support `--always`. After expiry, `open-workspace` again and follow [Native permission approval](#native-permission-approval).

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
| `xbridge status` | Show native MCP permissions/workspaces and daemon/bridge health |
| `xbridge status --fix [--project <path>]` | Show native status and human approval instructions; read-only, no daemon needed |

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
| `xbridge run [--device <title>] [--debugger]` | Build and run the current scheme       |
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

### Device Hub

| Command                                                    | Description                                      |
| ---------------------------------------------------------- | ------------------------------------------------ |
| `xbridge device-start <session> [device]`                  | Start a workspace-bound device session           |
| `xbridge device-session <device> <session>`                | Start a device session without a workspace       |
| `xbridge device-end <key>`                                 | End a device session                             |
| `xbridge device-install <key>`                             | Build, install, and run on the session device    |
| `xbridge device-interact <key> [command] [bundle-id]`      | Synthesize a device event (omit command to snapshot) |

`device-start` / `device-install` take `--workspace` when several workspaces are open. `device-session`, `device-end`, and `device-interact` do not.

Use Device Hub for taps, swipes, snapshots, and launch-only activate of an already installed app. Build and run with `xbridge run`. On Xcode 27.0.0, do not open a workspace-bound session to install or run the app.

### Advanced

| Command                                    | Description                  |
| ------------------------------------------ | ---------------------------- |
| `xbridge exec <file> <purpose> <code>`     | Execute a Swift code snippet |
| `xbridge preview <file> [index]`           | Render a SwiftUI preview     |
| `xbridge docs <query> [framework]`         | Search Apple Developer Documentation |

Specialized tools (localization, crash reports, entitlements) have no dedicated subcommand. Use `xbridge call <ToolName> [json]`.

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
# At most 100 tests are returned inline; all discovered tests are written to `fullTestListPath`.
xbridge --workspace workspace1 test
# A specific test can be outside the inline 100. Parentheses () are required:
xbridge --workspace workspace1 test-run MyTarget 'MyTests/testSomething()'
```

Swift Testing identifiers use `SuiteName/testName()` format without a module or target prefix. Pass the test target separately as the first `test-run` argument.

If the response and `fullTestListPath` artifact unexpectedly contain exactly 100 tests with `truncated: false`, Xcode's discovery snapshot may be incomplete. Force discovery through the test target's owning scheme, then return to the original scheme:

```bash
xbridge --workspace workspace1 switch-scheme Feature
xbridge --workspace workspace1 test-list
xbridge --workspace workspace1 switch-scheme App
xbridge --workspace workspace1 test-list
xbridge --workspace workspace1 test-run FeatureTests 'FeatureTests/testSomething()'
```

Running `test-run` while the owning scheme is active is also a reliable fallback. `GetTestList` has no target, name, pagination, or limit fields; do not pass unsupported filters through `xbridge call`.

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

### Run on a simulator

Classify the request before choosing a command:

- Launch an already installed app, with no fresh build → skip `device-install` and `run`. Activate with a quoted wait and the project's bundle ID (see [Drive a simulator](#drive-a-simulator-device-hub)).
- Build and run, reinstall, or run latest changes → `run`. On Xcode 27.0.0, do not use `device-start` + `device-install` to launch (see [Xcode 27.0.0 Device Hub bug](#xcode-2700-device-hub-bug-workspace-sessions-cannot-interact)).

Do not use RocketSim or `simctl install`/`launch`. Do not search DerivedData for `.app` bundles. Do not silently rebuild or install when a launch-only activate fails.

Resolve the destination from the request:

- A destination `displayTitle`, simulator name, or UDID → pass that title to `--device` only if it already appears in `list-destinations`. Do not create or clone simulators with `simctl`.
- Focused simulator or the currently selected Xcode destination → omit `--device`.
- Destination not specified → ask whether to use the currently selected Xcode destination or a named one from `list-destinations`. Do not pick one silently.

```bash
xbridge list-workspaces
xbridge --workspace workspace1 list-destinations
xbridge --workspace workspace1 run --device "iPhone 18 Pro" --debugger
xbridge --workspace workspace1 console
```

`--device` takes a `displayTitle` from `list-destinations`. Omit it to use the destination already selected in Xcode. On failure, inspect `issues` and `build-log`, report the failure, and stop. Do not bypass a failed `run` or `device-install` with `xcodebuild` or `simctl`.

### Drive a simulator (Device Hub)

Open a Device Hub session when the task needs a tap, swipe, snapshot, or a launch-only activate of an already installed app. If a build-and-run only needs the app running, stop after `run`.

Quote every interaction command as **one** shell argument. `device-interact` takes `<key> [command] [bundle-id]`; an unquoted `t 100 200` becomes command `t` and bundle ID `100`.

Build and run, then open a bare session for taps. Launch-only skips `run` and activates on that session instead:

```bash
xbridge list-workspaces
xbridge --workspace workspace1 list-destinations
xbridge --workspace workspace1 run --device "iPhone 18 Pro"
xbridge device-session "iPhone 18 Pro" "Verify Login Flow"
# → interactionSessionKey is the session name you passed

xbridge device-interact "Verify Login Flow"
# snapshot only — returns hierarchyPath + screenshotPath

xbridge device-interact "Verify Login Flow" "t 242 822"
# tap hitPoint from the latest hierarchy (never guess from the screenshot)

xbridge device-end "Verify Login Flow"
```

Launch-only activate uses the project's bundle ID as the third argument and a quoted wait, not `device-install` or `run`:

```bash
xbridge device-interact "Verify Login Flow" "w 1" com.example.App
```

`NotRun` after that wait means this activate did not show the app running. Do not treat it as proof the app is absent unless that was verified another way. Stop and tell the user. Do not silently rebuild or install.

If the app is backgrounded after launch (`applicationState: RunningInBackground`), activate it by passing the same bundle ID:

```bash
xbridge device-interact "Verify Login Flow" "t 242 822" com.example.App
```

#### Interaction commands

Xcode 27 `IDEDeviceInteraction` grammar (not English words). Pass the command as a single quoted argument. Unknown verbs fail with `Invalid command`.

| Command | Meaning |
| ------- | ------- |
| *(omit)* | Snapshot: hierarchy + screenshot. Does not change UI. |
| `t x y [duration]` | Tap. Optional duration in seconds. |
| `d x y` | Double tap. |
| `t x1 y1 f x2 y2 [duration]` | Swipe / flick. |
| `drag x1 y1 x2 y2 [holdDuration] [moveDuration]` | Drag / drop. |
| `sender keyboard kbd <text>` | Type. Must be the final command; spaces in the text are preserved. |
| `b <button> [duration]` | Hardware button. `b h` is Home. |
| `w seconds` | Wait. |
| `orientation value` | `portrait`, `portraitUpsideDown`, `landscapeLeft`, `landscapeRight`, `faceUp`, `faceDown`. |

iPhone-safe examples:

```bash
xbridge device-interact "Verify Login Flow" "t 242 822"
xbridge device-interact "Verify Login Flow" "t 100 500 f 100 300 0.3"
xbridge device-interact "Verify Login Flow" "sender keyboard kbd hello world"
xbridge device-interact "Verify Login Flow" "b h"
```

Do **not** use English verbs: `tap`, `swipe`, `scroll`, `type`, `text`, `home`, `longpress`. Those are labels in Apple's schema, not parser tokens. `c` (Digital Crown) and remote `r <button>` are not for iPhone (`Ensure the session device matches the expected platform`).

Always take coordinates from `hitPoint: {x, y}` in the latest hierarchy dump. Example: `Button, {{190.8, 795.0}, {103.3, 54.0}}, label: 'Messages', hitPoint: {242.4, 822.0}` → `t 242 822`.

After each interact, read `applicationState` and the new hierarchy. Confirm the expected control is `Selected` (or the screen title changed) before the next tap.

#### Session rules

- Build and run with `run`, then use `device-session` against the same destination for taps, swipes, or snapshots. For an already installed app, skip `run` and `device-install` and activate with `device-interact` using a quoted `w 1` and the project's bundle ID. On Xcode 27.0.0, do not use `device-start` + `device-install` to launch: workspace-bound sessions also cannot be interacted with or ended (see [Xcode 27.0.0 Device Hub bug](#xcode-2700-device-hub-bug-workspace-sessions-cannot-interact)). If `device-install` is used and fails, inspect `issues` and `build-log`, report the failure, and stop. Do not bypass it with `xcodebuild` or `simctl`.
- `sessionIdentifier` is a Title Case label (`Verify Login Flow`). It becomes `interactionSessionKey`.
- `deviceIdentifier` accepts a destination `displayTitle` from `list-destinations`, a simulator name, or a UDID.
- End the session with `device-end` as soon as the flow is done. Keeping it open is expensive.
- Idle expiry is Xcode's Device Hub session store (~120s; cleanup is async, so a session may still work at 125s and be gone by 180s). Pauses under two minutes are fine. After that, `device-session` again. Death is not caused by `xbridged` restart, workspace loss, or permission loss.
- If a later interact returns `Session not found`, start a new session. Do not retry the dead key.
- Apple's tool text tells you to spawn a `device-interaction` subagent. Drive the same commands from this CLI instead; do not look for a separate skill.

### Local simulator run (replaces sim-bridge)

1. `xbridge status` until `bridge : healthy`; inspect native status for server availability and the intended workspace. Open the project with `open-workspace` if needed.
2. `xbridge list-workspaces` — pick the entry whose path is inside the repo root. Pass `--workspace <id>` when more than one is open.
3. `list-schemes` / `list-destinations`. Use an explicit destination title, simulator name, or UDID only if it already appears there. Omit `--device` for the focused or currently selected Xcode destination. If the destination was not specified, ask whether to use the selected destination or a named one from `list-destinations`. Do not `simctl clone` unless the named simulator is missing from `list-destinations`.
4. If the request is launch-only, skip this step. Otherwise `xbridge --workspace <id> run --device "iPhone 18 Pro"`. Omit `--device` when the focused Xcode destination is the one to use. Add `--debugger` only when a debug session is needed. On failure, inspect `issues` and `build-log`, report the failure, and stop. Do not fall back to `xcodebuild` or `simctl`.
5. If there are no taps, swipes, snapshots, or launch-only activate to perform, stop. Do not start a Device Hub session.
6. If there are UI actions, or the request is launch-only, start a session against the destination, snapshot or activate, then act with quoted commands (see above). Launch-only activate is `device-interact "<session>" "w 1" <bundle-id>`. Do not invent behavior. Do not silently rebuild or install if that activate fails.
7. End the session with `device-end` as soon as the flow is done, then report.

Do not call `simctl list` or `rocketsim screen` to pick a simulator when `list-destinations` already has it. Snapshot once, then tap from that hierarchy.

> On Xcode 27.0.0, interacting with a workspace-bound session fails with `Session not found` — see [Xcode 27.0.0 Device Hub bug](#xcode-2700-device-hub-bug-workspace-sessions-cannot-interact). For build-and-run, launch with `run` first, then interact through a bare `device-session`. Launch-only still skips `run`.

## Troubleshooting

**xbridge not found**
Install with `brew tap 4rays/tap && brew install xbridge`.

**`xbridge status` shows bridge down or unhealthy**
Inspect `xcrun mcp-server status --format json` for server availability, permissions, pending requests, and workspaces. For GUI use, ensure Xcode is open with a project and MCP is enabled in **Xcode > Settings > Intelligence > Model Context Protocol**. The daemon auto-starts and retries on the next project command.

**Command returns `WAITING_FOR_PERMISSION`**
Use [Native permission approval](#native-permission-approval), ask the human to run the exact sudo command, wait for confirmation, then re-run the same command.

**Grant expired / “isn't approved to use Xcode's tools yet”**
Run `xbridge open-workspace /path/to/MyApp.xcodeproj` again and follow [Native permission approval](#native-permission-approval). Unsigned agents require 24-hour approval; durable trust is available only for signed agents and folders.

**`workspaceIdentifier is required`**
More than one workspace is open. Pass `--workspace <id>` from `xbridge list-workspaces`.

**No workspaces from `xbridge list-workspaces`**
Run `xbridge open-workspace MyApp.xcodeproj` first. Native status also lists open workspaces, including when the server is headless.

**Xcode MCP not enabled**
Go to **Xcode > Settings > Intelligence > Model Context Protocol** and enable Xcode Tools.

**MCP permission denied**
Inspect native status and follow [Native permission approval](#native-permission-approval). Do not clear permissions or revoke unrelated grants as a repair shortcut.

**`Invalid command: 'tap'` (or `swipe`, `type`, `home`)**
Those are English labels, not parser verbs. Use `t x y`, `t x1 y1 f x2 y2`, `sender keyboard kbd <text>`, `b h`. Quote the whole command as one argument.

**`Session not found` / `Session doesn't exist anymore`**
Xcode's Device Hub idle store expired the session (~120s, gone by ~180s) or it was ended. `device-session` again. Pauses under two minutes are fine. If the key was workspace-bound on Xcode 27.0.0, restarting the session will not help — use the [Device Hub bug recipe](#xcode-2700-device-hub-bug-workspace-sessions-cannot-interact).

**`applicationState: NotRun` or `RunningInBackground`**
For `RunningInBackground`, or a launch-only request, pass the project's bundle ID as the third `device-interact` argument. Launch-only activate is a quoted `w 1` plus that bundle ID. Do not treat `NotRun` after that wait as proof the app is absent unless verified another way, and do not silently rebuild or install. For a build-and-run request that has not launched yet, use `run`.

**`Unsupported command. Ensure the session device matches the expected platform`**
Crown (`c`) and some hardware (`r`, some `b` names) are not for iPhone. Use `t` / `drag` / `orientation`.

### Xcode 27.0.0 Device Hub bug: workspace sessions cannot interact

**Symptom.** A workspace-bound session (`device-start`) locks the device and `device-install` works, but `device-interact` and `device-end` on that key return `Session not found` while the device stays locked: `device already in use by a different session with key X`. Ghost locks accumulate, including pre-existing stale ones from long-gone sessions.

**Root cause.** The workspace-session path is broken in Xcode 27.0.0 Device Hub. `DeviceInteractionStartWorkspaceSession` registers the device lock, but its session entry is never findable by Synthesize/EndSession. Bare sessions (`DeviceInteractionStartSession`, no workspace) work fine for interact. Restarting Xcode Service does **not** fix workspace sessions — this is an Xcode bug, not stale bridge or daemon state.

**Working recipe.** Launch with `run`, then interact through a bare session. If a previous workspace-bound session left ghost locks, clear them before starting the bare session:

```bash
# 1. Build and launch without a workspace-bound Device Hub session.
xbridge --workspace workspace1 run --device "iPhone 18 Pro"

# 2. Only if ghost locks remain: DeviceHub.app ignores SIGTERM; SIGKILL it and Xcode relaunches it
#    automatically. The installed app keeps running on the simulator.
kill -9 "$(pgrep -f DeviceHub.app)"

# 3. Interact through a bare session (no workspace involved).
xbridge device-session "iPhone 18 Pro" "Bare"
# equivalent: xbridge call DeviceInteractionStartSession '{"sessionIdentifier":"Bare","deviceIdentifier":"iPhone 18 Pro"}'
xbridge device-interact "Bare" "t 242 822"
```

`device-session`, `device-interact`, and `device-end` never take `--workspace`. Keep the build-and-run flow (`run` → `device-session` → `device-interact` → `device-end`) after Xcode ships a fix. A launch-only request still skips `run` and `device-install`.

## Reporting back

After a simulator launch or Device Hub flow, report:

- Launch-only activate versus install/run, and whether it succeeded or failed.
- Workspace id, scheme, and destination title.
- Session name, when a session was started.
- When UI actions or verification were requested, the interact commands that ran and the observed `applicationState` and selected control (or screen title) afterward.

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

## Native permission approval

Use Xcode 27's permission-management CLI, not UI automation:

```bash
xcrun mcp-server status --format json
# Or native status plus instructions, without contacting the xbridge daemon:
xbridge status --fix --project /path/to/root
```

Read the pending requests and existing grants. Verify the pending agent's executable path is the intended `xbridged` installation and the pending folder is the intended project root. Do not approve a request based only on its display name. `--project` adds context for review; it does not filter requests or change permissions.

If no matching request is pending, run `xbridge open-workspace /path/to/MyApp.xcodeproj` to request access, then read native status again. Agent and folder requests may need separate approvals and may appear in sequence.

For each verified pending request, replace `<request-id>` with its actual ID and **give the human the exact command to run in their terminal**:

```bash
sudo xcrun mcp-server approve <request-id> --for-24-hours
```

Do not run sudo, request a password, configure passwordless sudo, or click an Allow dialog. Wait for the human's confirmation, re-read native status, and repeat only for a matching remaining request. Then retry the original workspace operation to confirm project access; global bridge health alone does not prove access to that project.

`--always` grants durable trust only to **signed agents and folders**. Unsigned agents, such as an unsigned `xbridged`, must use `--for-24-hours`. Offer durable trust only when the human wants it and the request supports it. Do not use `--unsafe-always-allow-all-agents`, clear all permissions, or broaden folder access to avoid approval.

If `--xcode-path` selects a different Xcode, use the same `DEVELOPER_DIR` for native status and the human's approval command. If `mcp-server` is unavailable, report that Xcode 27+ is required for native permission management. Do not fall back to Accessibility traversal.
