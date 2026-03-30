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
    targets: [
        .executableTarget(name: "HighlightBar")
    ]
)
