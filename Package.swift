// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "xbridge",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "xbridge", targets: ["xbridge"]),
    .executable(name: "xbridged", targets: ["xbridged"]),
    .library(name: "XbridgeDeviceAgent", targets: ["XbridgeDeviceAgent"])
  ],
  targets: [
    .executableTarget(
      name: "xbridge",
      dependencies: ["XbridgeCore", "XbridgeDeviceAgent"],
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
    .target(
      name: "XbridgeDeviceAgent",
      dependencies: ["XbridgeCore"],
      path: "Sources/XbridgeDeviceAgent"
    ),
    .testTarget(
      name: "XbridgeCoreTests",
      dependencies: ["XbridgeCore"],
      path: "Tests/XbridgeCoreTests"
    ),
    .testTarget(
      name: "xbridgeTests",
      dependencies: ["xbridge", "XbridgeCore", "XbridgeDeviceAgent"],
      path: "Tests/xbridgeTests"
    ),
    .testTarget(
      name: "XbridgeDeviceAgentTests",
      dependencies: ["XbridgeDeviceAgent", "XbridgeCore"],
      path: "Tests/XbridgeDeviceAgentTests",
      resources: [.copy("Fixtures")]
    )
  ],
  swiftLanguageModes: [.v6]
)
