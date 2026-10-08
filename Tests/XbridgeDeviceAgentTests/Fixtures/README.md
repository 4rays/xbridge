# Device Hub fixture contract

`circle-discover-hierarchy.txt`, `settings-search-hierarchy.txt`, and `device-response.json` are sanitized captures from Xcode 27.0 `DeviceInteractionSynthesize` on an iPhone 18 Pro simulator. They cover Circle's hierarchy and UIKit Settings' `CollectionView` plus `Keyboard Focused` search field grammar. `controls-hierarchy.txt` extends the same observed line grammar with the control-state tokens needed to test conservative behavior where the captured screens did not expose a secure field.

Reliable fields observed in the current Xcode format:

- response: `applicationState`, `hierarchyPath`, `screenshotPath`, and `logsPath`
- hierarchy header: application bundle identifier and UI orientation
- element structure: indentation, role, frame, optional identifier/label/value, state tokens, and `hitPoint`
- action eligibility: supported non-secure interactive role, no `Disabled`/`Hidden`/`NotHittable` token, and current geometry
- selection: the standalone `Selected` token
- scrolling: `ScrollView`, `CollectionView`, and `Table` roles; scroll-bar `Other` nodes remain passive evidence

Conservative fallbacks:

- Missing application identity is represented as absent; `--bundle-id` remains caller-owned.
- Focus, editability, and security are positive signals only. `TYPE_TEXT` requires `Focused` or UIKit's `Keyboard Focused`, a known editable field role, and an explicit non-secure result.
- Unknown properties remain in `rawSource` and do not make an element actionable.
- Missing/ambiguous semantics or geometry prevents execution rather than guessing.
- Choice heads are capped at 250 options (below the API maximum of 255); encoded requests are capped at 96 KiB and drop passive visible text first.
