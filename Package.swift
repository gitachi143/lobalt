// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, testable logic: duration parsing, timer math, session model.
        .target(
            name: "PulseKit",
            path: "Sources/PulseKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app itself: AppKit/SwiftUI shell, speech, overlay, menu bar.
        .executableTarget(
            name: "Pulse",
            dependencies: ["PulseKit"],
            path: "Sources/Pulse",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PulseKitTests",
            dependencies: ["PulseKit"],
            path: "Tests/PulseKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
