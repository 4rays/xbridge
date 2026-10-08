## Context

xbridge currently exposes Device Hub as five thin one-shot commands. `device-interact` can capture a screenshot and hierarchy or synthesize one command, but the caller must inspect each hierarchy, choose a hit point, issue an action, and repeat. The CLI sends one local RPC request per invocation; `xbridged` owns the long-lived `xcrun mcpbridge` connection and intentionally contains no product policy.

The compared Jev projects converge on a useful boundary: code owns perception, the finite action space, execution, freshness, and verification, while Jev supplies one bounded semantic judgment. Device Hub already provides the two inputs an iOS implementation needs: a textual accessibility hierarchy and a screenshot artifact after every interaction.

The hierarchy artifact is an Xcode-produced text format rather than a versioned xbridge model. Initial implementation therefore needs captured fixtures from supported Xcode versions before its parser contract is finalized.

## Goals / Non-Goals

**Goals:**

- Add a safe, inspectable natural-language control loop over an existing Device Hub session.
- Use the accessibility hierarchy as the primary source of visible evidence and actionable targets.
- Ask Jev for one operation plus speculative branch targets in a single request.
- Execute only code-owned Device Hub commands built from a fresh observation.
- Use exact text candidates and deterministic readback where the hierarchy exposes field values.
- Preserve enough artifacts to reproduce policy and parser failures offline.
- Keep existing Device Hub commands and the daemon transport behavior unchanged.

**Non-Goals:**

- Starting, installing, or ending Device Hub sessions automatically in the first version.
- Sending screenshots to Jev.
- Generating arbitrary field text with a second model.
- Treating Jev's `DONE` answer as independently verified success.
- Supporting cross-app discovery or enumerating installed applications.
- Adding OCR before hierarchy coverage is measured on representative SwiftUI and UIKit apps.
- Guaranteeing safe unattended operation on production accounts or irreversible workflows.

## Decisions

### 1. Add a high-level CLI workflow, not daemon-owned policy

The command will be:

```text
xbridge device-agent <session-key> <goal> [--act] [--bundle-id <id>]
  [--steps <n>] [--min-confidence <p>] [--text <value>]...
  [--trace <directory>]
```

Without `--act`, it captures one observation, asks Jev, prints the proposed action and probabilities, and exits without mutation. With `--act`, it runs the bounded loop. It uses but does not create, install into, or close the session.

The agent runner belongs to the `xbridge` process because it owns user intent, API credentials, cancellation, traces, and mutation policy. `xbridged` remains a narrow MCP transport. Moving the loop into the daemon would make cancellation and credential ownership harder and would broaden the daemon beyond its documented purpose.

A new `XbridgeDeviceAgent` library target will hold testable models, hierarchy parsing, state projection, action-space construction, Jev transport, response validation, runner logic, and tracing. The executable will provide a small adapter from that target's Device Hub protocol to `DaemonClient`.

### 2. Treat Device Hub artifacts as observations, not formatted terminal output

The Device Hub adapter will call `DeviceInteractionSynthesize` without an interaction command to observe. It will decode the MCP result, locate `hierarchyPath`, `screenshotPath`, and application state, read the hierarchy file, and return a typed observation. The parser will be fixture-driven and tolerate unknown properties while requiring the fields needed for an action.

Each parsed element will retain internally:

- hierarchy path or structural position
- role/type
- identifier, label, value, and traits when present
- frame and `hitPoint`
- enabled, selected, focused, secure, and editable signals when present
- raw source line for diagnostics

Jev will receive only a semantic projection:

- goal
- application state and active bundle identifier when available
- visible text in reading order
- indexed actionable elements with role, label, value/state, and supported operations
- focused editable field summary
- the last eight executed actions and whether the observable screen changed

Coordinates, artifact paths, screenshot data, raw element handles, and fingerprints remain executor-only data.

### 3. Accessibility first; OCR is a measured follow-up

The first version will use the Device Hub hierarchy for both evidence and action targets. Non-actionable text remains evidence but is never converted into a tap target merely because it has coordinates. Tappable targets require a supported interactive role, a valid current hit point, and no disabled or hidden signal.

Vision OCR will be considered after collecting hierarchy coverage metrics from representative SwiftUI, UIKit, web-view, and custom-rendered screens. If added, OCR items will carry provenance and will not silently replace accessibility targets. This avoids importing the macOS project's weaker "all visible text is clickable" behavior into the initial iOS design.

### 4. Use a small dynamic operation set

The initial operations are:

- `TAP`: choose a currently actionable hierarchy element.
- `TYPE_TEXT`: choose an exact candidate for the positively identified focused, non-secure editable field.
- `SCROLL_UP` and `SCROLL_DOWN`: choose an observed scroll region, or the root viewport when no region is exposed.
- `WAIT`: wait briefly and capture a new state.
- `DONE`: all goal requirements appear visibly satisfied.
- `BLOCKED`: no offered operation can make progress.

There is no generic iOS back operation; navigation back is a normal `TAP` on the observed control. Home, orientation changes, arbitrary hardware buttons, app switching, and direct coordinate actions remain available through low-level `device-interact` but are not offered to Jev initially.

Every observation produces one operation `Choice` and only the applicable speculative target questions: `tap_target`, `scroll_target`, and `text_value`. Target instructions explicitly state their assumed operation because TypeSafe questions are independent.

### 5. Prefer exact text selection

The policy will derive contiguous goal spans up to eight words and merge caller-provided repeated `--text` values. `TYPE_TEXT` is offered only when a non-secure editable field is positively focused and at least one candidate exists. Its target question includes `NONE`; selecting it stops with `needs_input` rather than guessing.

The executor creates `sender keyboard kbd <text>` itself, rejects unsupported control characters, and never allows model output to become an arbitrary Device Hub command. Secure fields are not offered in the initial version. Documentation will state that goal text and explicit candidates are sent to TypeSafe.

Generated text was rejected for the first version because exact candidates cover deterministic UI tests, avoid another provider and credential, and permit complete readback verification. A writer can be added later as a fallback behind a separate explicit option.

### 6. Re-observe before every mutation

The observation used for a Jev request may become stale during network latency. Before `TAP`, `TYPE_TEXT`, or scrolling, the runner will take another snapshot and uniquely resolve the selected target by semantic identity rather than reusing its old coordinates.

Target identity uses the strongest available combination of hierarchy path, stable identifier, role, label, value/state, and nearby structural context. The action uses the fresh target's hit point or frame. If the target disappeared, changed meaning, or became ambiguous, no input is dispatched; the runner re-decides from the fresh state. Three consecutive stale decisions stop as `unstable_ui`.

`DONE` is accepted only after a fresh snapshot confirms that the observation fingerprint is unchanged; otherwise the decision is discarded. The terminal outcome is named `model_done`, not `verified_success`.

Read-only snapshot and Jev requests may use bounded transport retries. A mutation request is never retried after an ambiguous transport failure because the input may already have executed.

### 7. Verify text mechanically and stop on uncertainty

The Device Hub interaction response supplies the post-action observation. After text entry, the runner will compare the complete readable value of the same field with the selected candidate. It may poll with bounded read-only snapshots for up to two seconds. If the field cannot be uniquely identified or its readable value does not match, the run stops as `input_unverified`; it does not type again.

The runner will also stop on:

- operation or consumed-target confidence below the configurable threshold for a mutation
- two consecutive low-confidence `WAIT`, `DONE`, or `BLOCKED` fallback waits against unchanged state
- `BLOCKED` or `NONE`/missing text
- repeated action against an unchanged semantic state
- three consecutive stale decisions
- session expiry
- step or decision budget exhaustion
- malformed Jev output or hierarchy artifacts

The default confidence threshold will be `0.5`; callers can tune it from `0...1`. Confidence is the minimum of the operation and consumed target confidence for targeted mutations. A low-confidence non-mutating decision is not trusted as a terminal judgment, but it is safe to spend a bounded wait step gathering fresh evidence. The fallback allowance resets when the semantic UI fingerprint changes.

### 8. Call TypeSafe directly and validate strictly

There is no current Swift SDK in this package, so the new target will use `URLSession` to call `https://api.typesafe.ai/v1/systemone` with `TYPESAFE_API_KEY` and `TYPESAFE_MODEL` (`jev-latest` by default). No new package dependency is needed.

The response validator will require:

- answer type `choice`
- selected choice present in the offered criteria
- exact probability keys matching the criteria
- finite values in `0...1`
- a distribution sum within tolerance of 1
- selected choice at the maximum probability

Only the target head selected by the operation is validated and consumed. Unused speculative heads cannot trigger execution.

The state and criteria will be capped deterministically before request construction: at most 250 options per head and a maximum encoded request size. Interactive controls are retained before passive text evidence when truncation is necessary.

### 9. Make traces first-class and local

Each run writes to an explicit `--trace` directory or a timestamped directory under `~/Library/Application Support/xbridge/device-agent-runs/`. Permissions will be owner-only. A run records:

- configuration excluding API credentials
- copied hierarchy and screenshot artifacts for each observation
- the exact redacted TypeSafe request and response
- normalized elements and fingerprints
- proposed and executed actions
- confidence, latency, stale retries, and terminal outcome

The trace writer will mark caller-provided text candidates as sensitive-by-default in the summary and avoid duplicating them beyond the request/action records required for reproduction. Secure-field contents are never recorded because secure fields are never typed.

### 10. Keep completion verification extensible

The generic command cannot prove every arbitrary goal. It will return the final hierarchy/screenshot paths and a `model_done` status. The core target will define an outcome-verifier seam so future test-oriented callers can provide deterministic predicates, but the first CLI will not pretend to supply one.

Task-specific verification remains ordinary code: for example, asserting a switch is selected, a title appeared, or a value equals an expected string.

## Risks / Trade-offs

- **Xcode hierarchy format changes** → Capture real fixtures first, parse only required fields, preserve unknown properties, and fail closed when actionable geometry cannot be recovered.
- **Accessibility omissions in custom views, games, canvases, or web content** → Measure coverage and add provenance-preserving Vision OCR only after the hierarchy-only baseline is reliable.
- **Race between final snapshot and Device Hub mutation** → Re-observe immediately before action, use fresh geometry, and stop on mismatches; document that Device Hub does not offer atomic compare-and-act.
- **Duplicate labels produce ambiguous targets** → Include identifier, role, value/state, structure, and region in identity; require a unique fresh match rather than choosing the first.
- **Device Hub sessions expire after roughly two minutes idle** → Keep calls sequential and fast, detect session-not-found distinctly, and require the caller to restart rather than silently creating a new session.
- **Jev can confidently choose the wrong action** → Use bounded candidates, configurable confidence, preview-by-default, no raw command generation, strict step/no-op limits, and explicit non-verification of `DONE`.
- **Goal or text candidates may contain sensitive data** → Document that policy state is sent to TypeSafe, refuse secure fields, keep API keys out of traces, and use owner-only trace permissions.
- **A second preflight snapshot increases latency and Device Hub calls** → Accept the cost for correctness in the first version; optimize only after measuring with preserved traces.
- **Physical devices can carry real accounts and side effects** → Require explicit `--act`, keep the operation set narrow, and recommend simulator-first use; high-impact workflow policies remain future work.

## Simulator Validation Evidence

Xcode 27.0 on an iPhone 18 Pro simulator exposed the intended Circle tab controls, scroll regions, UIKit Settings collection cells, and a `Keyboard Focused` search field through the accessibility hierarchy. A live exact-entry run typed and read back `General` without retrying the mutation. The trace measured three read-only snapshots at 218–294 ms, one keyboard mutation at 1,039 ms, Jev decisions at 286–733 ms, request bodies of 4,701–8,627 bytes, and no truncation. The workflow used three snapshot calls plus one mutation for the one-action run.

The observed hierarchy covered the controls needed for navigation, scrolling, focus, and exact text verification. A separate OCR fallback is not justified by this baseline; custom views with demonstrated accessibility omissions should motivate a separate provenance-preserving OCR change.

## Migration Plan

1. Capture and commit sanitized hierarchy fixtures from representative SwiftUI and UIKit screens using the existing low-level Device Hub commands.
2. Land the new library target and offline parser/state/action-space/policy validation tests without exposing a CLI command.
3. Add the preview-only `device-agent` command and verify requests/traces against fixture and live sessions.
4. Add `--act` with freshness checks, bounded execution, input verification, and terminal statuses.
5. Document the workflow and run a simulator-based manual acceptance matrix before recommending physical-device use.

Rollback is additive: remove or hide `device-agent`; the existing Device Hub commands and daemon protocol remain unchanged.

## Open Questions

- **Resolved from Xcode 27 fixtures:** indentation and role provide structure; frame and `hitPoint` provide current geometry; `identifier`, `label`, `value`, and standalone state tokens provide semantics. Focus, editability, security, enabled/selected state, and scrollability are accepted only when positively represented by known roles/tokens. Unknown fields remain in `rawSource`; missing or ambiguous semantics fail closed.
- **Application identity remains optional:** current captures include `Application bundle identifier:` in the hierarchy even when the response envelope reports `applicationState: NotRun`. The adapter represents absence explicitly and keeps `--bundle-id` as the caller-owned activation fallback rather than assuming the header is universal.
- **Request limits:** each Choice head is capped at 250 options, below TypeSafe's documented 255 maximum. The encoded body is capped at 96 KiB; deterministic truncation removes passive visible text before executable controls and records drop counts.
