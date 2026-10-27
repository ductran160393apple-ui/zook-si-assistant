// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AiAssistant",
    platforms: [.macOS(.v14)],
    targets: [
        // Header C của lõi Rust (sinh bằng UniFFI từ bản build chưa strip).
        .systemLibrary(name: "CAiAssistCore", path: "CAiAssistCore"),
        .executableTarget(
            name: "AiAssistant",
            dependencies: ["CAiAssistCore"],
            path: "Sources/AiAssistant",
            linkerSettings: [
                // Thư viện Rust: cargo build -p aiassist-core (debug = chưa strip).
                .linkedLibrary("aiassist_core"),
            ]
        ),
    ]
)
