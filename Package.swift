// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokscaleBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TokscaleBar", path: "Sources/TokscaleBar"),
        .testTarget(name: "TokscaleBarTests", dependencies: ["TokscaleBar"])
    ]
)
