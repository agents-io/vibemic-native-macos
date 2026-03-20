// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeMic",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VibeMic",
            path: "VibeMic/Sources",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
