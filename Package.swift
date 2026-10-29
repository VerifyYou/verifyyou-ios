// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VerifyYou",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "VerifyYou", targets: ["VerifyYou"])
    ],
    targets: [
        .target(name: "VerifyYou"),
        .testTarget(name: "VerifyYouTests", dependencies: ["VerifyYou"]),
    ]
)
