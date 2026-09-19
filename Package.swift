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
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(
            name: "PanaLux",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/PanaLux",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
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
