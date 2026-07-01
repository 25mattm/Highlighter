// swift-tools-version: 5.9
import PackageDescription
import Foundation

// The Mac App Store build is selected with the HB_APPSTORE=1 environment
// variable. That build is sandboxed and must not link Sparkle (the App Store
// bans third-party updaters), so we drop the Sparkle dependency, exclude the
// Sparkle-importing source, and define APPSTORE for the conditional code paths.
// With the variable unset, the package is the original direct-download config.
let isAppStore = ProcessInfo.processInfo.environment["HB_APPSTORE"] == "1"

let package = Package(
    name: "HighlightBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HighlightBar", targets: ["HighlightBar"])
    ],
    dependencies: isAppStore ? [] : [
        // Pinned exactly: Package.resolved is gitignored because it flip-flops
        // between the two build configs, so this is the only pin.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3")
    ],
    targets: [
        .executableTarget(
            name: "HighlightBar",
            dependencies: isAppStore ? [] : [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: isAppStore ? ["UpdaterController.swift"] : [],
            swiftSettings: isAppStore ? [.define("APPSTORE")] : []
        )
    ]
)
