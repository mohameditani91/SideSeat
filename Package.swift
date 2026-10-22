// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SideSeat",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "SideSeat", targets: ["SideSeat"])
    ],
    targets: [
        .target(name: "SideSeat"),
        .testTarget(name: "SideSeatTests", dependencies: ["SideSeat"])
    ]
)
