// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AudioRecorder",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "AudioRecorder", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
