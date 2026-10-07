// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UZeeSystem",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "UZeeSystem", targets: ["UZeeSystem"])],
    dependencies: [.package(path: "../UZeeCore")],
    targets: [
        // Swift 5 mode: Speech and AVFoundation callbacks predate Sendable; the adapters keep their own locking.
        .target(name: "UZeeSystem", dependencies: ["UZeeCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "UZeeSystemTests", dependencies: ["UZeeSystem"])
    ]
)
