// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "xhammer",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "xhammer", targets: ["xhammer"]),
    .executable(name: "xhammerd", targets: ["xhammerd"])
  ],
  targets: [
    .executableTarget(
      name: "xhammer",
      dependencies: ["XhammerCore"]
    ),
    .executableTarget(
      name: "xhammerd",
      dependencies: ["XhammerCore"]
    ),
    .target(
      name: "XhammerCore"
    ),
    .testTarget(
      name: "XhammerCoreTests",
      dependencies: ["XhammerCore"]
    )
  ],
  swiftLanguageModes: [.v6]
)
