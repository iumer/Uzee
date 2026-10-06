// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UZeeData",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "UZeeData", targets: ["UZeeData"])],
    dependencies: [
        .package(path: "../UZeeCore"),
        // Only third-party dependency (ARCHITECTURE §1). Exact version is pinned in Package.resolved.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "UZeeData", dependencies: [
            "UZeeCore",
            .product(name: "GRDB", package: "GRDB.swift")
        ]),
        .testTarget(name: "UZeeDataTests", dependencies: ["UZeeData"])
    ]
)
