// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyBoop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KeyBoop", targets: ["KeyBoop"])
    ],
    targets: [
        .target(
            name: "KeyBoopCore",
            resources: [.copy("Dictionaries")]
        ),
        .target(name: "KeyBoopBrand"),
        .executableTarget(
            name: "KeyBoop",
            dependencies: ["KeyBoopCore", "KeyBoopBrand"]
        ),
        .executableTarget(
            name: "KeyBoopIcon",
            dependencies: ["KeyBoopBrand"]
        ),
        .executableTarget(
            name: "KeyBoopSelfTest",
            dependencies: ["KeyBoopCore"]
        ),
    ]
)
