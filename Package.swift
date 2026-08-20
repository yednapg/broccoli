// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Broccoli",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BroccoliCore", targets: ["BroccoliCore"]),
        .executable(name: "Broccoli", targets: ["BroccoliApp"]),
        .executable(name: "BroccoliBenchmark", targets: ["BroccoliBenchmark"]),
    ],
    targets: [
        .target(
            name: "BroccoliCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "BroccoliApp",
            dependencies: ["BroccoliCore"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(name: "BroccoliBenchmark", dependencies: ["BroccoliCore"]),
        .testTarget(name: "BroccoliCoreTests", dependencies: ["BroccoliCore"]),
        .testTarget(name: "BroccoliAppTests", dependencies: ["BroccoliApp", "BroccoliCore"]),
    ],
    swiftLanguageModes: [.v6]
)
