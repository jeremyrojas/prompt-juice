// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PromptJuice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PromptJuice", targets: ["PromptJuice"])
    ],
    targets: [
        .executableTarget(
            name: "PromptJuice",
            path: "app/PromptJuice",
            exclude: [
                "Resources/Info.plist"
            ]
        ),
        .testTarget(
            name: "PromptJuiceTests",
            dependencies: ["PromptJuice"],
            path: "app/PromptJuiceTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
