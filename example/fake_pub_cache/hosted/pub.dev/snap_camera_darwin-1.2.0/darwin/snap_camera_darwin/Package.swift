// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "snap_camera_darwin",
    platforms: [
        .iOS("12.0"),
        .macOS("10.14"),
    ],
    products: [.library(name: "snap-camera-darwin", targets: ["snap_camera_darwin"])],
    targets: [.target(name: "snap_camera_darwin")]
)
