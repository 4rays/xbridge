# Releasing xhammer

## Steps

1. **Bump version** in `Sources/xhammer/main.swift` — update the string in the `version` handler to `xhammer X.Y.Z`. Do this **before** building.

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
   rm -rf /tmp/xhammer-bin && mkdir /tmp/xhammer-bin
   cp .build/release/xhammer .build/release/xhammerd /tmp/xhammer-bin/
   cd /tmp && tar -czf xhammer-X.Y.Z-macos.tar.gz xhammer-bin/
   shasum -a 256 xhammer-X.Y.Z-macos.tar.gz
   ```

5. **Create GitHub release and upload tarball:**

   ```sh
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "..." --latest
   gh release upload vX.Y.Z /tmp/xhammer-X.Y.Z-macos.tar.gz
   ```

6. **Update Homebrew formula** in `4rays/homebrew-tap`:
   - `url` → new tarball URL
   - `sha256` → output from step 4
   - `version` → new version

7. **Commit and push** the formula update.

## Notes

- Formula ships pre-built macOS binaries — no Xcode required to install.
- Tarball structure: `xhammer-bin/xhammer` + `xhammer-bin/xhammerd`.
- Homebrew cds into the single top-level dir (`xhammer-bin/`) on extract.
