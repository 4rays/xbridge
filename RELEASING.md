# Releasing xbridge

1. Bump the version in `Sources/xbridge/main.swift` before building.
2. Run `swift test` and `swift build -c release`. Check `xbridge --version`, the read-only `osascript scripts/allow-xcode-access.applescript` path, and that a source install's `xbridge skill` output exactly matches `skills/xbridge/SKILL.md`.
3. Commit and push the source changes, then tag that commit `vX.Y.Z` and push the tag.
4. The `Release` GitHub Actions workflow builds a macOS archive, publishes it to the GitHub release, and updates `4rays/homebrew-tap/Formula/xbridge.rb`. Wait for the workflow and verify the release asset and formula before reporting success. The workflow needs `HOMEBREW_TAP_TOKEN` with write access to the tap.
5. If the tap update fails, download the **published artifact**, calculate its SHA-256, update the formula's URL and hash, and ensure `bin.install "xbridge-allow"` and `pkgshare.install "xbridge-skill.md"` are present, then validate and push the tap change. Never calculate a checksum from a separate local build: archive bytes can differ.

The archive has one top-level `xbridge-bin/` containing `xbridge`, `xbridged`, the executable `xbridge-allow` AppleScript, and `xbridge-skill.md` copied from `skills/xbridge/SKILL.md`. Homebrew installs the Markdown into `share/xbridge/`; `make install` follows the same layout.
