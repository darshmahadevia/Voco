// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Voco",
    platforms: [.macOS("13.0")],
    products: [.library(name: "VocoCore", targets: ["VocoCore"])],
    targets: [
        .target(name: "VocoCore"),
        .testTarget(name: "VocoCoreTests", dependencies: ["VocoCore"])
    ]
)
