// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FaceMacOS",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "FaceMacOS",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/FaceMacOS",
            // Sparkle.framework is embedded in Contents/Frameworks by scripts/build.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
