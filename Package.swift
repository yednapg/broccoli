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
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.6"
        ),
    ],
    targets: [
        .target(
            name: "BroccoliCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "BroccoliApp",
            dependencies: [
                "BroccoliCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(name: "BroccoliBenchmark", dependencies: ["BroccoliCore"]),
        .testTarget(name: "BroccoliCoreTests", dependencies: ["BroccoliCore"]),
        .testTarget(
            name: "BroccoliAppTests",
            dependencies: ["BroccoliApp", "BroccoliCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../..",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
