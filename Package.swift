// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lobalt",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, testable logic: duration parsing, timer math, session model.
        .target(
            name: "LobaltKit",
            path: "Sources/LobaltKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app itself: AppKit/SwiftUI shell, speech, overlay, menu bar.
        .executableTarget(
            name: "Lobalt",
            dependencies: ["LobaltKit"],
            path: "Sources/Lobalt",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LobaltKitTests",
            dependencies: ["LobaltKit"],
            path: "Tests/LobaltKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
