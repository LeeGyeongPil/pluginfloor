// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cloud_core",
    platforms: [
        .macOS("11.0"),
    ],
    products: [.library(name: "cloud-core", targets: ["cloud_core"])],
    targets: [.target(name: "cloud_core")]
)
