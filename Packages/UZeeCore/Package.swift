// swift-tools-version: 6.2
import PackageDescription

// Pure Swift domain layer. No dependencies and no Apple-only frameworks,
// so its tests also run on Linux (CI job core-linux).
let package = Package(
    name: "UZeeCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "UZeeCore", targets: ["UZeeCore"])],
    targets: [
        .target(name: "UZeeCore"),
        .testTarget(name: "UZeeCoreTests", dependencies: ["UZeeCore"])
    ]
)
