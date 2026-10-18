// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_device_ai",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-device-ai", targets: ["flutter_device_ai"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_device_ai",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                // FoundationModels only exists on iOS/macOS 26+; link it weakly.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])
            ]
        )
    ]
)
