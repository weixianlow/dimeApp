// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DimeFX",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "DimeFX", targets: ["DimeFX"])
    ],
    targets: [
        .target(name: "DimeFX"),
        .testTarget(name: "DimeFXTests", dependencies: ["DimeFX"])
    ]
)
