// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacLaunchControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacLaunchControl", targets: ["LaunchctlDesktopApp"])
    ],
    targets: [
        .executableTarget(
            name: "LaunchctlDesktopApp",
            path: "Sources/LaunchctlDesktopApp"
        )
    ]
)
