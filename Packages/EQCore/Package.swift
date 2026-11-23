// swift-tools-version: 6.2
// EQCore: EQ Studio's EQ logic with no screen in it, a Swift port of web/eq.js (Q2 Theme Studio's,
// GPL-3.0): a preset's text, its limits and its curve, as Q2 Pod's patch/peq.c reads and plays them.
import PackageDescription

let package = Package(
    name: "EQCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "EQCore", targets: ["EQCore"])],
    targets: [
        .target(name: "EQCore"),
        .testTarget(name: "EQCoreTests", dependencies: ["EQCore"], resources: [.copy("presets.json.gz")]),
    ]
)
