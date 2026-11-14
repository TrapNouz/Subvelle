// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SubspaceCore", platforms: [.iOS("26.0"), .macOS(.v14)], products: [.library(name: "SubspaceCore", targets: ["SubspaceCore"])], targets: [.target(name: "SubspaceCore", path: "Subspace/Core"), .testTarget(name: "SubspaceCoreTests", dependencies: ["SubspaceCore"], path: "Tests/SubspaceCoreTests")])
