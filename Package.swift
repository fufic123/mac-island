// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacIsland",
            path: "Sources/MacIsland"
        )
    ]
)
