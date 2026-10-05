## 1. Device Hub Contract Discovery

- [ ] 1.1 Capture raw `DeviceInteractionSynthesize` response envelopes and hierarchy artifacts from current Xcode for representative SwiftUI and UIKit screens, including buttons, navigation, switches, text fields, secure fields, disabled controls, duplicate labels, scroll views, and Unicode text.
- [x] 1.2 Sanitize and add hierarchy/response fixtures to the test target, documenting which fields reliably represent application identity, focus, editability, security, enabled/selected state, structure, frames, and hit points.
- [x] 1.3 Resolve the design's hierarchy-format open questions from the fixture evidence and record conservative parser fallbacks and request-size constants.

## 2. Device Agent Module and Models

- [x] 2.1 Add `XbridgeDeviceAgent` and `XbridgeDeviceAgentTests` targets to `Package.swift`, depending only on `XbridgeCore` and Apple system frameworks.
- [x] 2.2 Define Sendable models for Device Hub artifacts, parsed hierarchy elements, observations, semantic identities, actions, policy decisions, history entries, terminal outcomes, and typed agent errors.
- [x] 2.3 Define injectable protocols for Device Hub observation/execution, Jev policy evaluation, tracing, timing/sleep, and optional task-specific outcome verification.
- [x] 2.4 Add validated configuration models for session key, goal, preview/act mode, bundle ID, step and decision budgets, confidence threshold, text candidates, retry limits, and trace destination.

## 3. Device Hub Observation Parsing

- [x] 3.1 Implement MCP Device Hub result decoding that extracts application state plus hierarchy and screenshot paths from both structured content and JSON-wrapped MCP text.
- [x] 3.2 Implement the fixture-driven hierarchy parser, preserving unknown source properties while failing closed when required action geometry or semantics are missing.
- [x] 3.3 Normalize hierarchy elements into reading order, focused-field state, passive visible evidence, actionable controls, and scroll regions with explicit provenance.
- [x] 3.4 Compute deterministic observation and target fingerprints that exclude temporary artifact paths and unstable formatting.
- [x] 3.5 Add parser and normalization tests for every captured fixture, malformed artifacts, unknown properties, duplicates, missing geometry, and stable fingerprint behavior.

## 4. State Projection and Dynamic Action Space

- [x] 4.1 Build the compact Jev state projection with app state, visible text, actionable elements, focused field, and the latest eight executed-action effects while excluding screenshots, paths, coordinates, credentials, and raw prior answers.
- [x] 4.2 Implement dynamic operation and speculative target criteria for `TAP`, `TYPE_TEXT`, `SCROLL_UP`, `SCROLL_DOWN`, `WAIT`, `DONE`, and `BLOCKED`.
- [x] 4.3 Implement exact text candidate extraction from goal spans up to eight words, repeated explicit values, de-duplication, `NONE`, secure-field refusal, and unsupported-control-character validation.
- [x] 4.4 Implement deterministic candidate and encoded-request size limits that retain executable controls before passive text and report truncation metadata.
- [x] 4.5 Add tests proving passive text cannot become a tap target, unavailable operations are omitted, speculative premises are explicit, history is bounded, secure fields are excluded, and truncation is stable.

## 5. TypeSafe Jev Policy

- [x] 5.1 Implement a direct `URLSession` System One client using `TYPESAFE_API_KEY`, `TYPESAFE_MODEL`, the fixed HTTPS endpoint, bounded timeouts, and read-only retry rules without logging authorization data.
- [x] 5.2 Encode one request per cycle containing the operation question and every applicable speculative target question over the same state.
- [x] 5.3 Implement strict consumed-Choice validation for answer type, exact keys, finite bounded values, normalized sum, selected option, and argmax consistency.
- [x] 5.4 Map validated answers to typed decisions, consume only the target head selected by the operation, and compute mutation confidence from operation and consumed-target confidence.
- [x] 5.5 Add policy tests with a fake HTTP transport for valid answers, each malformed-distribution case, transient retries, non-retryable failures, unused target heads, low confidence, and model-name/usage capture.

## 6. Device Hub Adapter and Guarded Executor

- [x] 6.1 Add a CLI-side Device Hub adapter that sends snapshot and interaction calls through `DaemonClient`, classifies session expiry and ambiguous transport failures, and never retries mutations.
- [x] 6.2 Implement fresh-target resolution using hierarchy path, stable identifier, role, label, value/state, and structural context, requiring a unique match before mutation.
- [x] 6.3 Implement code-owned Device Hub command construction for fresh taps, exact keyboard text, region-relative vertical swipes, and waits; reject arbitrary model commands and stale coordinates.
- [x] 6.4 Implement post-entry polling and exact complete-value verification for the same readable field, stopping without retyping when verification fails or remains unavailable.
- [x] 6.5 Add executor tests for fresh, changed, missing, and ambiguous targets; geometry changes; command encoding; uncertain mutation failures; session expiry; and successful/failed/unreadable text verification.

## 7. Bounded Agent Loop and Tracing

- [x] 7.1 Implement preview mode as one observation and one policy decision with no mutation.
- [x] 7.2 Implement active mode with preflight observation, stale-decision re-evaluation, post-action observation reuse, bounded waits, and action history recording.
- [x] 7.3 Implement terminal outcomes for `model_done`, `blocked`, `needs_input`, `low_confidence`, `stuck`, `unstable_ui`, `input_unverified`, `session_expired`, `ambiguous_mutation`, `step_limit`, `decision_limit`, observation failure, and invalid policy response.
- [x] 7.4 Require a fresh unchanged fingerprint before accepting `DONE`, and add the optional verifier seam without claiming generic verified success.
- [x] 7.5 Implement owner-only run directories that copy Device Hub artifacts and record redacted configuration, normalized observations, requests, responses, decisions, actions, timings, retries, verification, truncation, and final outcome.
- [x] 7.6 Add end-to-end runner tests with fake Device Hub and policy clients for preview, successful multi-step navigation, stale recovery, no-op detection, all terminal guards, trace completeness, and cancellation.

## 8. CLI and Documentation

- [x] 8.1 Add command-specific parsing and help for `device-agent <session-key> <goal>` with `--act`, `--bundle-id`, `--steps`, `--min-confidence`, repeated `--text`, and `--trace`, preserving all existing global and Device Hub command syntax.
- [x] 8.2 Wire the CLI command to the Device Hub adapter, TypeSafe client, runner, human-readable progress, final artifacts, and exit behavior while keeping API credentials in the CLI process.
- [x] 8.3 Update `README.md` with the explicit `device-start` → `device-install` → `device-agent` → `device-end` workflow, preview-by-default behavior, environment variables, privacy boundaries, statuses, and non-verification of `DONE`.
- [x] 8.4 Update `skills/xbridge/SKILL.md` with when to use the agent versus manual `device-interact`, text-candidate handling, simulator-first guidance, trace locations, and recovery instructions.
- [x] 8.5 Add regression tests proving existing low-level Device Hub commands still emit their current MCP tool names and argument keys.

## 9. Validation and Live Acceptance

- [x] 9.1 Run `swift-format lint -r Sources Tests`, `swift test`, and `swift build -c release`; fix all new diagnostics and record the commands in the change handoff.
- [x] 9.2 Run offline replay tests against all committed hierarchy fixtures with network and Device Hub transports mocked.
- [x] 9.3 On a simulator session, verify preview causes no mutation, then exercise tap navigation, scrolling, exact text entry/readback, model completion reporting, blocked state, and step/confidence limits against a representative app.
- [x] 9.4 Exercise stale-target and session-expiry paths deliberately and confirm no action is retried or sent to a replacement session.
- [x] 9.5 Review traces to confirm screenshots never enter TypeSafe requests, API credentials are absent, secure fields are excluded, and run-directory permissions are owner-only.
- [x] 9.6 Measure hierarchy coverage, per-step latency, Device Hub call count, request size, and Jev latency; use the results to decide whether a separate OCR-fallback change is justified.
