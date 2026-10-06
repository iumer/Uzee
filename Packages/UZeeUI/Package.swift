// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UZeeUI",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "UZeeUI", targets: ["UZeeUI"])],
    dependencies: [.package(path: "../UZeeCore")],
    targets: [
        .target(name: "UZeeUI", dependencies: ["UZeeCore"]),
        .testTarget(name: "UZeeUITests", dependencies: ["UZeeUI"])
    ]
)
