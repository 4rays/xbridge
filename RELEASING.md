# Releasing xbridge

1. Bump the version in `Sources/xbridge/main.swift` before building.
2. Run `swift test` and `swift build -c release`. Check `xbridge --version` and the read-only `osascript scripts/allow-xcode-access.applescript` path.
3. Commit and push the source changes, then tag that commit `vX.Y.Z` and push the tag.
4. The `Release` GitHub Actions workflow builds a macOS archive, publishes it to the GitHub release, and updates `4rays/homebrew-tap/Formula/xbridge.rb`. Wait for the workflow and verify the release asset and formula before reporting success. The workflow needs `HOMEBREW_TAP_TOKEN` with write access to the tap.
5. If the tap update fails, download the **published artifact**, calculate its SHA-256, update the formula's URL, version, hash, and `bin.install "xbridge-allow"` line, then validate and push the tap change. Never calculate a checksum from a separate local build: archive bytes can differ.

The archive has one top-level `xbridge-bin/` containing `xbridge`, `xbridged`, and the executable `xbridge-allow` AppleScript. `make install` installs the same three commands from a source checkout.
