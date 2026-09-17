// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PanaLux",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PanaLux", targets: ["PanaLux"])
    ],
    targets: [
        .executableTarget(
            name: "PanaLux",
            path: "Sources/PanaLux",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Network"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "PanaLuxTests",
            dependencies: ["PanaLux"],
            path: "Tests/PanaLuxTests"
        )
    ]
)
