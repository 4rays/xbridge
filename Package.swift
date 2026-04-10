// swift-tools-version: 6.3

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
      dependencies: ["XhammerCore"],
      path: "Sources/xhammer"
    ),
    .executableTarget(
      name: "xhammerd",
      dependencies: ["XhammerCore"],
      path: "Sources/xhammerd"
    ),
    .target(
      name: "XhammerCore",
      path: "Sources/XhammerCore"
    ),
    .testTarget(
      name: "XhammerCoreTests",
      dependencies: ["XhammerCore"],
      path: "Tests/XhammerCoreTests"
    ),
    .testTarget(
      name: "xhammerTests",
      dependencies: ["XhammerCore"],
      path: "Tests/xhammerTests"
    )
  ],
  swiftLanguageModes: [.v6]
)
