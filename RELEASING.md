# Releasing xbridge

## Steps

1. **Bump version** in `Sources/xbridge/main.swift` — update the string in the `version` handler to `xbridge X.Y.Z`. Do this **before** building.

2. **Build release binaries:**

   ```sh
   swift build -c release
   ```

3. **Tag and push:**

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. **Package binaries:**

   ```sh
   rm -rf /tmp/xbridge-bin && mkdir /tmp/xbridge-bin
   cp .build/release/xbridge .build/release/xbridged /tmp/xbridge-bin/
   cd /tmp && tar -czf xbridge-X.Y.Z-macos.tar.gz xbridge-bin/
   shasum -a 256 xbridge-X.Y.Z-macos.tar.gz
   ```

5. **Create GitHub release and upload tarball:**

   ```sh
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "..." --latest
   gh release upload vX.Y.Z /tmp/xbridge-X.Y.Z-macos.tar.gz
   ```

6. **Update Homebrew formula** (`4rays/homebrew-tap/Formula/xbridge.rb`):
   - `url` → new tarball URL (github.com/4rays/xbridge/releases/...)
   - `sha256` → output from step 4
   - `version` → new version
   - `bin.install` → simplify to plain installs (no `=>` rename needed from v0.1.3+):

     ```ruby
     bin.install "xbridge"
     bin.install "xbridged"
     ```

   > **Note:** v0.1.2 formula used `"xhammer" => "xbridge"` rename syntax because that
   > tarball predated the project rename. From v0.1.3 onward the tarball contains
   > `xbridge`/`xbridged` directly — drop the rename arrows.

7. **Commit and push** the formula update.

## Notes

- Formula ships pre-built macOS binaries — no Xcode required to install.
- Tarball structure: `xbridge-bin/xbridge` + `xbridge-bin/xbridged`.
- Homebrew cds into the single top-level dir (`xbridge-bin/`) on extract.
