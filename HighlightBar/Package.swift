// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HighlightBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HighlightBar", targets: ["HighlightBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "HighlightBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ]
        )
    ]
)
