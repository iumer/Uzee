// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UZeeSystem",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "UZeeSystem", targets: ["UZeeSystem"])],
    dependencies: [.package(path: "../UZeeCore")],
    targets: [
        .target(name: "UZeeSystem", dependencies: ["UZeeCore"]),
        .testTarget(name: "UZeeSystemTests", dependencies: ["UZeeSystem"])
    ]
)
