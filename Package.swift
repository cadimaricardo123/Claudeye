// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Claudy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Claudy",
            path: "Sources/Claudy",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
