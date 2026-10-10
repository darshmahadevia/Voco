// swift-tools-version: 6.0
import PackageDescription
import Foundation

let environment = ProcessInfo.processInfo.environment
let moonshineInclude = environment["VOCO_MOONSHINE_INCLUDE"] ?? ""
let moonshineLibrary = environment["VOCO_MOONSHINE_LIBRARY"] ?? ""
let whisperInclude = environment["VOCO_WHISPER_INCLUDE"] ?? ""
let ggmlInclude = environment["VOCO_GGML_INCLUDE"] ?? ""
let whisperLibrary = environment["VOCO_WHISPER_LIBRARY"] ?? ""
let ggmlLibrary = environment["VOCO_GGML_LIBRARY"] ?? ""
let ggmlBaseLibrary = environment["VOCO_GGML_BASE_LIBRARY"] ?? ""
let ggmlCPULibrary = environment["VOCO_GGML_CPU_LIBRARY"] ?? ""
let ggmlMetalLibrary = environment["VOCO_GGML_METAL_LIBRARY"] ?? ""
let ggmlBLASLibrary = environment["VOCO_GGML_BLAS_LIBRARY"] ?? ""

var cFlags: [String] = []
for include in [moonshineInclude, whisperInclude, ggmlInclude].filter({ !$0.isEmpty }) {
    cFlags += ["-Xcc", "-I", "-Xcc", include]
}

let archives = [whisperLibrary, ggmlLibrary, ggmlBaseLibrary, ggmlCPULibrary, ggmlMetalLibrary, ggmlBLASLibrary]
    .filter({ !$0.isEmpty })
let libraryDirectories = Set(([moonshineLibrary] + archives.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().path
}).filter({ !$0.isEmpty }))
var linkFlags: [String] = []
for libraryDirectory in libraryDirectories.sorted() {
    linkFlags += ["-L", libraryDirectory]
}
for archive in archives {
    linkFlags += ["-Xlinker", "-force_load", "-Xlinker", archive]
}
linkFlags += [
    "-framework", "Accelerate",
    "-framework", "AppKit",
    "-framework", "ApplicationServices",
    "-framework", "AVFoundation",
    "-framework", "CoreML",
    "-framework", "Foundation",
    "-framework", "Metal",
    "-framework", "Network",
    "-framework", "Security",
    "-framework", "SystemConfiguration",
    "-lc++", "-lz", "-lsqlite3",
]

let package = Package(
    name: "VocoNative",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.9.1"),
    ],
    targets: [
        .systemLibrary(name: "Moonshine", path: "Moonshine"),
        .systemLibrary(name: "Whisper", path: "Whisper"),
        .executableTarget(
            name: "VocoNative",
            dependencies: [
                .product(name: "VocoCore", package: "Voco"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                "Moonshine",
                "Whisper",
            ],
            path: "Sources",
            swiftSettings: [.unsafeFlags(cFlags)],
            linkerSettings: [.unsafeFlags(linkFlags)]
        ),
    ]
)
