// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FaceMacOS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FaceMacOS",
            path: "Sources/FaceMacOS"
        )
    ],
    swiftLanguageModes: [.v5]
)
