// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Hvalia", platforms: [.macOS("14.0")],
    products: [.library(name: "HvaliaCore", targets: ["HvaliaCore"]), .executable(name: "Hvalia", targets: ["Hvalia"])],
    targets: [.target(name: "HvaliaCore"), .executableTarget(name: "Hvalia", dependencies: ["HvaliaCore"]), .executableTarget(name: "HvaliaChecks", dependencies: ["HvaliaCore"], path: "Tests/HvaliaCoreTests")])
