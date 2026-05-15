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
        .package(path: "../../swift-primitives/swift-ascii-primitives"),
        .package(path: "../../swift-primitives/swift-glob-primitives"),
        .package(path: "../../swift-primitives/swift-linter-primitives"),
        .package(path: "../../swift-primitives/swift-manifest-primitives"),
        .package(path: "../../swift-primitives/swift-package-primitives"),
        .package(path: "../../swift-primitives/swift-standard-library-extensions"),
        .package(path: "../../swift-primitives/swift-terminal-primitives"),
        .package(path: "../../swift-primitives/swift-version-primitives"),
        .package(path: "../../swift-iso/swift-iso-9945"),
        .package(path: "../../swift-microsoft/swift-windows-32"),
        .package(path: "../../swift-standards/swift-spm-standard"),
        .package(path: "../../swift-standards/swift-uri-standard"),
        .package(path: "../swift-environment"),
        .package(path: "../swift-file-system"),
        .package(path: "../swift-json"),
        .package(path: "../swift-kernel"),
        .package(path: "../swift-manifests"),
        .package(path: "../swift-process"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.5.0")),
    ],
    targets: [
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
                .product(name: "ASCII Primitives", package: "swift-ascii-primitives"),
                .product(name: "Glob Primitives", package: "swift-glob-primitives"),
                .product(name: "Glob Primitives Standard Library Integration", package: "swift-glob-primitives"),
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "Manifest Primitives", package: "swift-manifest-primitives"),
                .product(name: "Package Primitives", package: "swift-package-primitives"),
                .product(name: "Environment", package: "swift-environment"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "Manifest Executable", package: "swift-manifests"),
                .product(name: "Manifest Loader", package: "swift-manifests"),
                .product(name: "Manifest Resolver", package: "swift-manifests"),
                .product(name: "Process", package: "swift-process"),
                .product(name: "SPM Standard", package: "swift-spm-standard"),
                .product(name: "URI Standard", package: "swift-uri-standard"),
                .product(name: "Version Primitives", package: "swift-version-primitives"),
                .product(name: "Version Primitives Standard Library Integration", package: "swift-version-primitives"),
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
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "Package Primitives", package: "swift-package-primitives"),
                .product(name: "Standard Library Extensions", package: "swift-standard-library-extensions"),
                .product(name: "Terminal Primitives", package: "swift-terminal-primitives"),
                .product(name: "URI Standard Library Integration", package: "swift-uri-standard"),
                .product(name: "Version Primitives Standard Library Integration", package: "swift-version-primitives"),
            ]
        ),
        .executableTarget(
            name: "Linter CLI",
            dependencies: [
                "Linter",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Kernel", package: "swift-kernel"),
            ]
        ),
        .testTarget(
            name: "Linter Core Tests",
            dependencies: [
                "Linter Core",
                "Linter Reporter Text",
                "Linter Reporter SARIF",
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "URI Standard", package: "swift-uri-standard"),
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
