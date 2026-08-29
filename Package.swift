// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-linter",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
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
        .library(
            name: "Linter Reporter Structured",
            targets: ["Linter Reporter Structured"]
        ),
        .executable(
            name: "swift-linter",
            targets: ["Linter CLI"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-molecules/swift-ascii.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-cardinal.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-glob.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-linter.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-manifest.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-package.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-atoms/swift-standard-library-extensions.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-terminal.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-version.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swift-iso/swift-iso-9945.git", branch: "main"),
        .package(url: "https://github.com/swift-microsoft/swift-windows-32.git", branch: "main"),
        .package(url: "https://github.com/swift-standards/swift-spm-standard.git", branch: "main"),
        .package(url: "https://github.com/swift-standards/swift-uri-standard.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-environment.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-file-system.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-json.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-kernel.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-manifests.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-paths.git", branch: "main"),
        .package(
            url: "https://github.com/swift-compositions/swift-package-manager.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swift-compositions/swift-process.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0"),
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            .upToNextMajor(from: "1.5.0")
        ),
    ],
    targets: [
        .target(
            name: "Linter Reporter Text",
            dependencies: [
                .target(name: "Linter Core"),
                .product(name: "Cardinal", package: "swift-cardinal"),
                .product(name: "Linter", package: "swift-linter"),
                .product(name: "Terminal", package: "swift-terminal"),
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
                .target(name: "Linter Core"),
                .target(name: "Linter Reporter Text"),
                .product(name: "Linter", package: "swift-linter"),
                .product(name: "Terminal", package: "swift-terminal"),
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
            name: "Linter Reporter Structured",
            dependencies: [
                .target(name: "Linter Core"),
                .product(name: "JSON", package: "swift-json"),
                .product(name: "Paths", package: "swift-paths"),
            ]
        ),
        .target(
            name: "Linter Core",
            dependencies: [
                .product(name: "ASCII", package: "swift-ascii"),
                .product(name: "Glob", package: "swift-glob"),
                .product(
                    name: "Glob Standard Library Integration",
                    package: "swift-glob"
                ),
                .product(name: "Linter", package: "swift-linter"),
                .product(name: "Manifest", package: "swift-manifest"),
                .product(name: "Package", package: "swift-package"),
                .product(name: "Environment", package: "swift-environment"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "Manifest Executable", package: "swift-manifests"),
                .product(name: "Manifest Loader", package: "swift-manifests"),
                .product(name: "Manifest Resolver", package: "swift-manifests"),
                .product(name: "Package Manager", package: "swift-package-manager"),
                .product(name: "Process", package: "swift-process"),
                .product(name: "SPM Standard", package: "swift-spm-standard"),
                .product(name: "URI Standard", package: "swift-uri-standard"),
                .product(name: "Version", package: "swift-version"),
                .product(
                    name: "Version Standard Library Integration",
                    package: "swift-version"
                ),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Linter",
            dependencies: [
                .target(name: "Linter Core"),
                .target(name: "Linter Reporter Text"),
                .target(name: "Linter Reporter SARIF"),
                .target(name: "Linter Reporter Structured"),
                .product(name: "Environment", package: "swift-environment"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "JSON", package: "swift-json"),
                .product(name: "Package", package: "swift-package"),
                .product(name: "Process", package: "swift-process"),
                .product(
                    name: "Standard Library Extensions",
                    package: "swift-standard-library-extensions"
                ),
                .product(name: "Terminal", package: "swift-terminal"),
                .product(name: "URI Standard Library Integration", package: "swift-uri-standard"),
                .product(
                    name: "Version Standard Library Integration",
                    package: "swift-version"
                ),
            ]
        ),
        .executableTarget(
            name: "Linter CLI",
            dependencies: [
                .target(name: "Linter"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Environment", package: "swift-environment"),
                .product(name: "Kernel", package: "swift-kernel"),
                .product(
                    name: "Windows 32 Kernel Directory",
                    package: "swift-windows-32",
                    condition: .when(platforms: [.windows])
                ),
                .product(
                    name: "Windows 32 Kernel Terminal",
                    package: "swift-windows-32",
                    condition: .when(platforms: [.windows])
                ),
            ]
        ),
        .executableTarget(
            name: "swift-linter-report-fixture",
            dependencies: [
                .target(name: "Linter")
            ],
            path: "Tests/Fixtures/report-format-executable"
        ),
        .executableTarget(
            name: "swift-linter-invalid-control-fixture",
            dependencies: [
                .target(name: "Linter")
            ],
            path: "Tests/Fixtures/report-format-invalid-executable"
        ),
        .executableTarget(
            name: "swift-linter-bundle-fixture",
            dependencies: [
                .target(name: "Linter")
            ],
            path: "Tests/Fixtures/bundle-channel-executable"
        ),
        .executableTarget(
            name: "swift-linter-bundle-empty-fixture",
            dependencies: [
                .target(name: "Linter")
            ],
            path: "Tests/Fixtures/bundle-channel-empty-executable"
        ),
        .testTarget(
            name: "Linter Core Tests",
            dependencies: [
                .target(name: "Linter"),
                .target(name: "Linter Core"),
                .target(name: "Linter Reporter Text"),
                .target(name: "Linter Reporter SARIF"),
                .product(name: "Environment", package: "swift-environment"),
                .product(name: "Linter", package: "swift-linter"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "JSON", package: "swift-json"),
                .product(name: "Process", package: "swift-process"),
                .product(name: "SPM Standard", package: "swift-spm-standard"),
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
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
