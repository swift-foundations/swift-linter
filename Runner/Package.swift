// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "standard-runner",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "runner", targets: ["runner"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-linter.git", branch: "main"),
        .package(
            url: "https://github.com/swift-primitives/swift-primitives-linter-rules.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-standards/swift-standards-linter-rules.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-foundations/swift-institute-linter-rules.git",
            branch: "main"
        ),
    ],
    targets: [
        .executableTarget(
            name: "runner",
            dependencies: [
                .product(name: "Linter", package: "swift-linter"),

                .product(name: "Linter Primitives Rules", package: "swift-primitives-linter-rules"),
                .product(name: "Linter Standards Rules", package: "swift-standards-linter-rules"),
                .product(name: "Linter Institute Rules", package: "swift-institute-linter-rules"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings =
        (target.swiftSettings ?? []) + [
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault"),
            .enableUpcomingFeature("MemberImportVisibility"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        ]
}
