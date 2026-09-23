// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TechFinderCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TechFinderCore", targets: ["TechFinderCore"]),
    ],
    targets: [
        .target(name: "TechFinderCore"),
        // Dependency-free self-check, runnable with only the Command Line Tools: `swift run CoreCheck`.
        .executableTarget(name: "CoreCheck", dependencies: ["TechFinderCore"]),
        .testTarget(name: "TechFinderCoreTests", dependencies: ["TechFinderCore"]),
    ]
)
