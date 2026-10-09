// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenLatchCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "OpenLatchCore", targets: ["OpenLatchCore"])],
    targets: [
        .target(name: "OpenLatchCore", resources: [.process("en.lproj"), .process("de.lproj")]),
        .testTarget(name: "OpenLatchCoreTests", dependencies: ["OpenLatchCore"])
    ]
)
