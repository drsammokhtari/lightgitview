// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "LightGitView",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "LightGitView", path: "Sources/LightGitView")]
)
