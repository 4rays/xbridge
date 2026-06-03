// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "xbridge",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "xbridge", targets: ["xbridge"]),
    .executable(name: "xbridged", targets: ["xbridged"])
  ],
  targets: [
    .executableTarget(
      name: "xbridge",
      dependencies: ["XbridgeCore"],
      path: "Sources/xbridge"
    ),
    .executableTarget(
      name: "xbridged",
      dependencies: ["XbridgeCore"],
      path: "Sources/xbridged"
    ),
    .target(
      name: "XbridgeCore",
      path: "Sources/XbridgeCore"
    ),
    .testTarget(
      name: "XbridgeCoreTests",
      dependencies: ["XbridgeCore"],
      path: "Tests/XbridgeCoreTests"
    ),
    .testTarget(
      name: "xbridgeTests",
      dependencies: ["XbridgeCore"],
      path: "Tests/xbridgeTests"
    )
  ],
  swiftLanguageModes: [.v6]
)
