## Why

Device Hub exposes reliable iOS snapshots and low-level interactions, but callers still have to inspect each hierarchy and choose every command manually. A Jev-backed device agent can turn a natural-language goal into bounded, inspectable Device Hub actions while keeping observation, execution, freshness checks, and verification in xbridge code.

## What Changes

- Add a goal-driven `device-agent` workflow that operates on an existing Device Hub session and repeatedly observes, decides, validates, executes, and records actions.
- Convert Device Hub hierarchy artifacts into a compact semantic state and a dynamic, operation-specific action space for TypeSafe Jev.
- Ask Jev for the next operation and speculative targets in one request, strictly validate its selected distributions, and confidence-gate execution.
- Prefer exact text candidates supplied by the goal or caller; do not add generative text to the initial implementation.
- Re-observe before every mutation, resolve the selected target from fresh hierarchy data, and stop rather than retry uncertain or stale mutations.
- Produce structured traces and explicit terminal outcomes such as model completion, blocked, low confidence, stale/unstable UI, unverified input, session expiry, and step limit.
- Document the workflow in the README and xbridge skill without changing the existing low-level Device Hub commands.

## Capabilities

### New Capabilities

- `jev-device-agent`: Goal-driven iOS Device Hub automation using structured hierarchy state, speculative Jev choices, guarded execution, and replayable traces.

### Modified Capabilities

None.

## Impact

- Adds a new first-class CLI workflow alongside `device-start`, `device-install`, `device-interact`, and `device-end`.
- Adds testable hierarchy parsing, state projection, policy, runner, trace, and Device Hub adapter components to the Swift package.
- Adds direct HTTPS communication with TypeSafe using `TYPESAFE_API_KEY` and `TYPESAFE_MODEL`, without introducing a third-party runtime dependency.
- Reads hierarchy and screenshot artifact paths returned by Xcode Device Hub but sends only structured text state to Jev.
- Leaves the daemon's responsibility unchanged: it remains the long-lived Xcode MCP transport and does not own agent policy or run state.
