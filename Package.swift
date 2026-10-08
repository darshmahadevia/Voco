// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Voco",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Voco", targets: ["Voco"])],
    targets: [
        .target(name: "VocoCore"),
        .executableTarget(name: "Voco", dependencies: ["VocoCore"]),
        .testTarget(name: "VocoCoreTests", dependencies: ["VocoCore"])
    ]
)
