// swift-tools-version: 6.2
// La versión de herramientas 6.2 es la primera que entiende `.iOS(.v26)`.
import PackageDescription

let package = Package(
    name: "GolfCore",
    // macOS está para que `swift test` funcione en el runner del CI, que es un Mac.
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "GolfCore", targets: ["GolfCore"]),
    ],
    targets: [
        .target(name: "GolfCore"),
        .testTarget(name: "GolfCoreTests", dependencies: ["GolfCore"]),
    ]
)
