// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrzybEngine",
    defaultLocalization: "pl",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GrzybEngine", targets: ["GrzybEngine"]),
        .library(name: "GrzybData", targets: ["GrzybData"]),
        .library(name: "GrzybStore", targets: ["GrzybStore"]),
        .executable(name: "score-cli", targets: ["score-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "GrzybEngine",
            resources: [.copy("Resources/knowledge")]
        ),
        .target(name: "GrzybData", dependencies: ["GrzybEngine"]),
        .target(
            name: "GrzybStore",
            dependencies: ["GrzybEngine", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(name: "score-cli", dependencies: ["GrzybEngine", "GrzybData"]),
        .testTarget(
            name: "GrzybEngineTests",
            dependencies: ["GrzybEngine", "GrzybData"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "GrzybStoreTests", dependencies: ["GrzybStore", "GrzybEngine"]),
    ],
    swiftLanguageModes: [.v5]
)
