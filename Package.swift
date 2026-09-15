// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Unlocker",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Unlocker", targets: ["Unlocker"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.5")],
    targets: [
        .executableTarget(name: "UnlockerProbe", dependencies: ["UnlockerCore", "UnlockerPlatform"]),
        .target(name: "UnlockerCore"),
        .target(name: "UnlockerPlatform", dependencies: ["UnlockerCore"]),
        .executableTarget(name: "Unlocker", dependencies: ["UnlockerCore", "UnlockerPlatform", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "UnlockerCoreTests", dependencies: ["UnlockerCore"]),
        .testTarget(name: "UnlockerPlatformTests", dependencies: ["UnlockerPlatform", "UnlockerCore"])
    ]
)
