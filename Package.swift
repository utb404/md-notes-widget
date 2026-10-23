// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDWidgets",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MDWidgets",
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        )
    ]
)
