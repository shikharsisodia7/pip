// swift-tools-version: 5.10
// FROZEN. PipKit is pure logic (Foundation only) so `swift test` runs on the Mac in seconds.
import PackageDescription

let package = Package(
    name: "PipKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PipKit", targets: ["PipKit"])],
    targets: [
        .target(name: "PipKit"),
        .testTarget(name: "PipKitTests", dependencies: ["PipKit"]),
    ]
)
