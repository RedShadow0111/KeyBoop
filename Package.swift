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
        .executableTarget(
            name: "KeyBoop",
            dependencies: ["KeyBoopCore"]
        ),
        .executableTarget(
            name: "KeyBoopSelfTest",
            dependencies: ["KeyBoopCore"]
        ),
    ]
)
