// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NexoLLM",
    platforms: [.macOS(.v14)],
    targets: [
        // Prebuilt llama.cpp (Metal) from https://github.com/ggml-org/llama.cpp/releases
        .binaryTarget(name: "llama", path: "Vendor/build-apple/llama.xcframework"),
        // Prebuilt whisper.cpp (Metal) from https://github.com/ggml-org/whisper.cpp/releases — the engine of the
        // optional Audio Context plugin. Its speech model is downloaded separately, only after explicit consent.
        .binaryTarget(name: "whisper", path: "Vendor/whisper/build-apple/whisper.xcframework"),
        .executableTarget(
            name: "NexoLLM",
            dependencies: ["llama", "whisper"],
            path: "Sources/NexoLLM",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(name: "NexoLLMTests", dependencies: ["NexoLLM"], path: "Tests/NexoLLMTests"),
    ]
)
