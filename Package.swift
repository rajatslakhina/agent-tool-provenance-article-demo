// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProvenanceGate",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ProvenanceGate", targets: ["ProvenanceGate"]),
    ],
    targets: [
        .target(name: "ProvenanceGate"),
        .testTarget(name: "ProvenanceGateTests", dependencies: ["ProvenanceGate"]),
    ]
)
