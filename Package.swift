// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacIsland",
    platforms: [.macOS(.v14)],
    targets: [
        // Sessions, the hook protocol and the Unix socket server. No AppKit or SwiftUI, so it's
        // testable on its own.
        .target(
            name: "IslandCore",
            path: "Sources/IslandCore"
        ),
        // The app: window over the notch, UI, terminal focusing, first-run setup.
        .executableTarget(
            name: "MacIsland",
            dependencies: ["IslandCore"],
            path: "Sources/MacIsland"
        ),
        // Behaviour checks for the core: `swift run IslandCoreChecks`. An executable, since the
        // Command Line Tools have neither XCTest nor the Swift Testing macros.
        .executableTarget(
            name: "IslandCoreChecks",
            dependencies: ["IslandCore"],
            path: "Checks/IslandCoreChecks"
        ),
    ]
)
