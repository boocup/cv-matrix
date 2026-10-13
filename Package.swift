// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CVMatrix",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CVMatrix", path: "Sources/CVMatrix")
    ]
)
