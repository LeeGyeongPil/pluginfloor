// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "file_drop",
    platforms: [
        .iOS(.v13),
    ],
    products: [.library(name: "file-drop", targets: ["file_drop"])],
    targets: [.target(name: "file_drop")]
)
