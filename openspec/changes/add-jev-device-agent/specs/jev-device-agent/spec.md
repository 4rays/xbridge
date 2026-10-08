## ADDED Requirements

### Requirement: Existing-session agent workflow
The system SHALL provide a `device-agent` command that accepts an existing Device Hub interaction session key and a nonempty natural-language goal. The command SHALL NOT implicitly start, install into, end, or recreate the session.

#### Scenario: Preview is the default
- **WHEN** the user invokes `device-agent` with a valid session key and goal without `--act`
- **THEN** the system captures one current observation, obtains one Jev decision, prints the proposed operation and relevant confidence/probabilities, and sends no mutating Device Hub command

#### Scenario: Explicit execution
- **WHEN** the user invokes `device-agent` with `--act`
- **THEN** the system runs the bounded observe-decide-validate-execute loop against that session until a terminal outcome occurs

#### Scenario: Session lifecycle remains caller-owned
- **WHEN** an agent run reaches any terminal outcome
- **THEN** the system leaves the Device Hub session open for the caller to inspect or end explicitly

### Requirement: Typed Device Hub observation
The system SHALL decode each Device Hub snapshot result into a typed observation containing application state, hierarchy content, screenshot and hierarchy artifact locations, observation time, normalized elements, and a semantic fingerprint. Missing fields needed for safe execution SHALL produce an observation error rather than guessed values.

#### Scenario: Snapshot artifacts are available
- **WHEN** Device Hub returns readable hierarchy and screenshot artifact paths
- **THEN** the system reads and normalizes the hierarchy and retains both artifact paths without sending screenshot bytes to Jev

#### Scenario: Required artifact is missing
- **WHEN** Device Hub omits the hierarchy path or the hierarchy file cannot be read
- **THEN** the run stops with an observation error and dispatches no action

#### Scenario: Unknown hierarchy properties
- **WHEN** a hierarchy line contains properties the parser does not recognize
- **THEN** the parser preserves diagnostic source data, ignores the unknown properties, and continues if all fields required for the element's offered operations remain valid

### Requirement: Accessibility-first semantic projection
The system SHALL use the Device Hub accessibility hierarchy as the initial source of visible evidence and actionable targets. It SHALL expose passive text as evidence but SHALL offer a tap target only for a supported interactive, enabled, visible element with a valid current hit point or frame.

#### Scenario: Passive label is evidence only
- **WHEN** the hierarchy contains visible static text without an interactive role
- **THEN** the text appears in Jev state but is absent from `tap_target` criteria

#### Scenario: Actionable control becomes a target
- **WHEN** the hierarchy contains an enabled visible button with a label and hit point
- **THEN** the button appears as an indexed `TAP` target with its semantic role and state

#### Scenario: Disabled control is excluded
- **WHEN** the hierarchy marks a control disabled or not hittable
- **THEN** the control is retained as relevant state when useful but is not offered as an executable target

### Requirement: Compact Jev state
The system SHALL send Jev a deterministic semantic state containing the goal, available app identity, visible text, indexed actionable elements, focused-field summary, and at most the eight most recent executed actions. It MUST keep coordinates, artifact paths, screenshot data, API credentials, and execution fingerprints out of model state.

#### Scenario: Recent action effects are included
- **WHEN** an action has executed and a post-action observation exists
- **THEN** the next Jev state includes the operation, human-readable target label, non-sensitive text metadata, and whether the semantic screen changed

#### Scenario: Raw prior answers are omitted
- **WHEN** several Jev decisions have occurred
- **THEN** subsequent state contains their executed consequences but not complete prior Jev responses or probability distributions

#### Scenario: Request exceeds configured limits
- **WHEN** normalized state or criteria would exceed the configured candidate or encoded-size limit
- **THEN** the system applies deterministic truncation that retains actionable controls before passive evidence and reports truncation in the trace

### Requirement: Speculative operation and target choices
For each decision cycle, the system SHALL send one TypeSafe request containing an operation `Choice` and all applicable speculative target `Choice` questions. Each target question SHALL explicitly name its assumed operation, and code SHALL consume only the target corresponding to the selected operation.

#### Scenario: Tap and text branches are available
- **WHEN** the screen has tappable elements and a focused editable field with text candidates
- **THEN** one request contains `operation`, `tap_target`, and `text_value` questions evaluated over the same state

#### Scenario: Unused target cannot execute
- **WHEN** Jev selects `TAP` while also returning a `text_value` answer
- **THEN** the system validates and consumes `tap_target` only and ignores `text_value` for execution

#### Scenario: Operation has no target branch
- **WHEN** Jev selects `WAIT`, `DONE`, or `BLOCKED`
- **THEN** the system does not require or consume a target answer

### Requirement: Strict Jev response validation
The system MUST validate every consumed `Choice` answer before execution. The selected key MUST be offered, probability keys MUST exactly match offered criteria, values and confidence MUST be finite within `0...1`, probabilities MUST sum to one within tolerance, and the selected key MUST have maximal probability.

#### Scenario: Valid distribution
- **WHEN** Jev returns a complete normalized distribution whose selected choice is maximal
- **THEN** the policy returns a typed decision

#### Scenario: Missing probability key
- **WHEN** a consumed answer omits any offered criterion or includes an unknown key
- **THEN** the run stops with an invalid-policy-response error and dispatches no action

#### Scenario: Nonmaximal selected choice
- **WHEN** a consumed answer selects a choice with lower probability than another offered choice
- **THEN** the run stops with an invalid-policy-response error and dispatches no action

### Requirement: Dynamic bounded operations
The initial policy SHALL offer only operations supported by the current observation from `TAP`, `TYPE_TEXT`, `SCROLL_UP`, `SCROLL_DOWN`, `WAIT`, `DONE`, and `BLOCKED`. It SHALL NOT allow Jev to provide raw Device Hub commands or arbitrary coordinates.

#### Scenario: No focused field
- **WHEN** no non-secure editable field is positively focused
- **THEN** `TYPE_TEXT` is absent from operation criteria

#### Scenario: Scroll region is present
- **WHEN** the hierarchy identifies a usable scroll region
- **THEN** applicable scroll operations and a speculative scroll-region target are offered

#### Scenario: Device command construction
- **WHEN** a fresh typed decision is ready to execute
- **THEN** ordinary code builds the appropriate Device Hub grammar from fresh code-owned geometry and the model's bounded choice

### Requirement: Exact text candidate selection
The system SHALL derive text candidates from contiguous goal spans of up to eight words and repeated caller-provided `--text` values. Jev SHALL select a complete exact candidate or `NONE`; it SHALL NOT generate field text in the initial implementation.

#### Scenario: Goal contains the field value
- **WHEN** the goal contains an appropriate value for the focused field
- **THEN** that exact span is available in `text_value` criteria and the selected value is copied unchanged into the Device Hub typing command

#### Scenario: Caller supplies a value
- **WHEN** the user provides one or more `--text` values
- **THEN** those exact values are added to the candidate set and documented as content sent to TypeSafe

#### Scenario: Candidate coverage is insufficient
- **WHEN** Jev selects `NONE` because no candidate is an appropriate complete value
- **THEN** the run stops as `needs_input` and does not type

#### Scenario: Secure field is focused
- **WHEN** the hierarchy positively identifies the focused field as secure or password-like
- **THEN** `TYPE_TEXT` is not offered and secure contents are neither sent to Jev nor written to traces

### Requirement: Freshness validation before mutation
The system MUST capture a fresh observation before every tap, text entry, or scroll and uniquely resolve the selected target against that observation. It MUST use fresh geometry and MUST NOT dispatch the mutation when target meaning changed, disappeared, or became ambiguous.

#### Scenario: Target remains fresh
- **WHEN** the selected control uniquely matches the fresh hierarchy with the same semantic identity
- **THEN** the executor uses the fresh control's hit point or frame to build the action

#### Scenario: Target changed during inference
- **WHEN** the selected control no longer matches the fresh hierarchy
- **THEN** the decision is discarded, no mutation occurs, and the policy re-decides from the fresh observation

#### Scenario: Repeated stale decisions
- **WHEN** three consecutive decisions become stale before execution
- **THEN** the run stops as `unstable_ui`

#### Scenario: Completion state changed
- **WHEN** Jev selects `DONE` but a fresh snapshot has a different semantic fingerprint
- **THEN** the system discards `DONE` and re-decides rather than reporting completion

### Requirement: No ambiguous mutation retry
The system MUST NOT automatically retry a Device Hub mutation after a transport error that leaves execution uncertain. Read-only snapshots and TypeSafe requests MAY use bounded retry policies.

#### Scenario: Mutation response is lost
- **WHEN** the Device Hub connection fails after a mutation request is sent and execution cannot be determined
- **THEN** the run stops with an ambiguous-mutation error and does not resend the command

#### Scenario: Read-only request transiently fails
- **WHEN** a snapshot or Jev request fails with a configured transient error before any mutation
- **THEN** the system may retry within its bounded read-only retry budget

### Requirement: Text-entry verification
After `TYPE_TEXT`, the system SHALL use post-action observations to verify the full readable value of the same field. It SHALL stop without retyping when the value cannot be confirmed within the bounded verification window.

#### Scenario: Complete value matches
- **WHEN** the post-action hierarchy uniquely identifies the same field and its complete value equals the selected candidate
- **THEN** the action is marked verified and the next decision may proceed

#### Scenario: Value does not match
- **WHEN** the verification window expires without an exact readable match
- **THEN** the run stops as `input_unverified` and does not issue another typing command

#### Scenario: Field value is unreadable
- **WHEN** Device Hub does not expose a readable value for the target field
- **THEN** the run stops as `input_unverified` rather than assuming success

### Requirement: Confidence and loop guards
The system SHALL gate each consumed mutating decision on a configurable confidence threshold and SHALL enforce step, decision, wait, stale, and repeated-no-op bounds. A low-confidence non-mutating `WAIT`, `DONE`, or `BLOCKED` decision SHALL trigger a bounded fallback wait and fresh observation rather than being accepted or immediately terminating the run.

#### Scenario: Target confidence is low
- **WHEN** either operation confidence or the consumed target confidence is below the configured threshold
- **THEN** the run stops as `low_confidence` before mutation

#### Scenario: Non-mutating confidence is low
- **WHEN** Jev selects `WAIT`, `DONE`, or `BLOCKED` below the configured threshold
- **THEN** the runner waits and observes again without mutation, and stops as `low_confidence` only after two consecutive fallback waits against unchanged state

#### Scenario: Repeated no-op
- **WHEN** the same action is selected against an unchanged semantic state for the configured repetition limit
- **THEN** the run stops as `stuck`

#### Scenario: Step budget is exhausted
- **WHEN** the run reaches its configured maximum executed actions
- **THEN** it stops as `step_limit` without dispatching another action

#### Scenario: Session expires
- **WHEN** Device Hub reports that the interaction session no longer exists
- **THEN** the run stops as `session_expired` and does not create or substitute a session

### Requirement: Honest completion status
The generic agent SHALL distinguish model-judged completion from independently verified success. A `DONE` answer SHALL produce `model_done` and return final observation artifacts; it SHALL NOT claim `verified_success` without an explicit task-specific verifier.

#### Scenario: Stable model completion
- **WHEN** Jev selects `DONE` and the fresh observation is unchanged
- **THEN** the run stops as `model_done`, prints the final hierarchy and screenshot locations, and states that completion was not independently verified

#### Scenario: Task-specific verifier is supplied
- **WHEN** a future caller supplies a deterministic verifier through the core verifier interface
- **THEN** only that verifier may upgrade a terminal outcome to verified success

### Requirement: Replayable local traces
The system SHALL write an owner-readable trace for every preview or active run, either to the requested directory or the xbridge application-support run directory. The trace MUST exclude API credentials and MUST include sufficient normalized input, policy output, execution, and artifact evidence to diagnose the run offline.

#### Scenario: Trace records a decision
- **WHEN** Jev returns a decision
- **THEN** the trace contains the normalized state, questions, response, requested and returned model names, probabilities, confidence, latency, target identity, and any truncation metadata

#### Scenario: Trace records an action
- **WHEN** an action is dispatched
- **THEN** the trace records the code-built Device Hub operation, preflight fingerprint, post-action fingerprint when available, verification result, and terminal status without recording API credentials

#### Scenario: Device Hub artifact is temporary
- **WHEN** Device Hub returns readable hierarchy or screenshot artifacts
- **THEN** the trace copies them into the run directory before relying on them for later replay

### Requirement: Existing Device Hub compatibility
The change SHALL preserve the behavior and syntax of `device-start`, `device-session`, `device-install`, `device-interact`, and `device-end`.

#### Scenario: Low-level manual workflow
- **WHEN** a user continues to invoke the existing Device Hub commands without `device-agent`
- **THEN** xbridge emits the same MCP tools and arguments as before this change

#### Scenario: Agent feature is unavailable
- **WHEN** `TYPESAFE_API_KEY` is missing
- **THEN** `device-agent` fails with an actionable configuration error while all existing commands remain usable
