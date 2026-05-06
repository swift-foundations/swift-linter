// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-linter",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "Linter",
            targets: ["Linter"]
        ),
        .library(
            name: "Linter Rule Unchecked",
            targets: ["Linter Rule Unchecked"]
        ),
        .library(
            name: "Linter Rule Cardinal",
            targets: ["Linter Rule Cardinal"]
        ),
        .library(
            name: "Linter Rule RawValue",
            targets: ["Linter Rule RawValue"]
        ),
        .library(
            name: "Linter Rule ResultBuilder",
            targets: ["Linter Rule ResultBuilder"]
        ),
        .library(
            name: "Linter Reporter Text",
            targets: ["Linter Reporter Text"]
        ),
        .library(
            name: "Linter Reporter SARIF",
            targets: ["Linter Reporter SARIF"]
        ),
        .executable(
            name: "swift-linter",
            targets: ["Linter CLI"]
        ),
    ],
    dependencies: [
        .package(path: "../../swift-primitives/swift-linter-primitives"),
        .package(path: "../../swift-primitives/swift-terminal-primitives"),
        .package(path: "../../swift-iso/swift-iso-9945"),
        .package(path: "../../swift-microsoft/swift-windows-32"),
        .package(path: "../../swift-standards/swift-uri-standard"),
        .package(path: "../swift-environment"),
        .package(path: "../swift-file-system"),
        .package(path: "../swift-json"),
        .package(path: "../swift-manifest"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.5.0")),
    ],
    targets: [
        .target(
            name: "Linter Rule Unchecked",
            dependencies: [
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Linter Rule Cardinal",
            dependencies: [
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Linter Rule RawValue",
            dependencies: [
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Linter Rule ResultBuilder",
            dependencies: [
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Linter Reporter Text",
            dependencies: [
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "Terminal Primitives", package: "swift-terminal-primitives"),
                .product(
                    name: "ISO 9945 Kernel Terminal",
                    package: "swift-iso-9945",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])
                ),
                .product(
                    name: "Windows 32 Kernel Terminal",
                    package: "swift-windows-32",
                    condition: .when(platforms: [.windows])
                ),
            ]
        ),
        .target(
            name: "Linter Reporter SARIF",
            dependencies: [
                "Linter Reporter Text",
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "Terminal Primitives", package: "swift-terminal-primitives"),
                .product(name: "JSON", package: "swift-json"),
                .product(
                    name: "ISO 9945 Kernel Terminal",
                    package: "swift-iso-9945",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])
                ),
                .product(
                    name: "Windows 32 Kernel Terminal",
                    package: "swift-windows-32",
                    condition: .when(platforms: [.windows])
                ),
            ]
        ),
        .target(
            name: "Linter Core",
            dependencies: [
                "Linter Rule Unchecked",
                "Linter Rule Cardinal",
                "Linter Rule RawValue",
                "Linter Rule ResultBuilder",
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "Environment", package: "swift-environment"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "Manifest", package: "swift-manifest"),
                .product(name: "URI Standard", package: "swift-uri-standard"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Linter",
            dependencies: [
                "Linter Core",
                "Linter Reporter Text",
                "Linter Reporter SARIF",
                "Linter Rule Unchecked",
                "Linter Rule Cardinal",
                "Linter Rule RawValue",
                "Linter Rule ResultBuilder",
            ]
        ),
        .executableTarget(
            name: "Linter CLI",
            dependencies: [
                "Linter",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "Linter Rule Unchecked Tests",
            dependencies: [
                "Linter Rule Unchecked",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "Linter Rule Cardinal Tests",
            dependencies: [
                "Linter Rule Cardinal",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "Linter Rule RawValue Tests",
            dependencies: [
                "Linter Rule RawValue",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "Linter Rule ResultBuilder Tests",
            dependencies: [
                "Linter Rule ResultBuilder",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
