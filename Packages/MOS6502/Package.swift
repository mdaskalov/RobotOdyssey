// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MOS6502",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MOS6502", targets: ["MOS6502"]),
    ],
    targets: [
        .target(name: "MOS6502"),
        .testTarget(name: "MOS6502Tests", dependencies: ["MOS6502"]),
    ]
)
