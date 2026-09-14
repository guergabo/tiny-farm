// swift-tools-version:5.9
import PackageDescription

// The simulation lives in TinyFarmCore so it can be unit tested on macOS
// without booting a simulator. The SwiftUI app in App/ compiles the same
// sources directly (see Scripts/build_app.sh).
let package = Package(
    name: "TinyFarm",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TinyFarmCore", targets: ["TinyFarmCore"])
    ],
    targets: [
        .target(name: "TinyFarmCore"),
        .testTarget(name: "TinyFarmCoreTests", dependencies: ["TinyFarmCore"]),
    ]
)
