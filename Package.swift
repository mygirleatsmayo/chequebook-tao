// swift-tools-version:5.9
// This package covers ONLY the platform-independent core (models, math,
// parsers) so the logic can be compiled and unit-tested on Linux/CI quickly.
// The macOS app itself is built from ChequebookTao.xcodeproj, which compiles
// Sources/Core + Sources/App together.
import PackageDescription

let package = Package(
    name: "ChequebookCore",
    products: [
        .library(name: "ChequebookCore", targets: ["ChequebookCore"]),
    ],
    targets: [
        .target(
            name: "ChequebookCore",
            path: "Sources/Core"
        ),
        .testTarget(
            name: "ChequebookCoreTests",
            dependencies: ["ChequebookCore"],
            path: "Tests/CoreTests"
        ),
    ]
)
