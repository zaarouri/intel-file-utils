// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "intel-file-utils",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "intel-file-utils", targets: ["intel-file-utils"])
    ],
    targets: [
        .executableTarget(
            name: "intel-file-utils",
            path: "Sources"
        )
    ]
)
