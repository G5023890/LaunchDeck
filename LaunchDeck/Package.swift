// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LaunchDeck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LaunchDeck", targets: ["LaunchctlDesktopApp"])
    ],
    targets: [
        .executableTarget(
            name: "LaunchctlDesktopApp",
            path: "Sources/LaunchctlDesktopApp"
        )
    ]
)
