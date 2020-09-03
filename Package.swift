// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "ShapeScript",
    platforms: [
        .macOS(.v10_13),
    ],
    products: [
        .library(name: "ShapeScript", targets: ["ShapeScript"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/Euclid.git", .upToNextMinor(from: "0.3.4")),
    ],
    targets: [
        .target(name: "ShapeScript", dependencies: ["Euclid"], path: "ShapeScript"),
        .testTarget(name: "ShapeScriptTests", dependencies: ["ShapeScript"], path: "ShapeScriptTests"),
    ]
)
