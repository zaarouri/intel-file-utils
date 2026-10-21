// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "floating-utils-intel-mac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "floating-utils-intel-mac", targets: ["floating-utils-intel-mac"])
    ],
    targets: [
        .executableTarget(
            name: "floating-utils-intel-mac",
            path: "Sources"
        )
    ]
)
