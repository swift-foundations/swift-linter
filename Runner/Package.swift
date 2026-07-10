// swift-tools-version: 6.3.3
import PackageDescription

// ===----------------------------------------------------------------------===//
//
// Phase-3 "standard runner" — the full-bake executable that bundles the engine
// (Linter) + SwiftSyntax + the standard primitives rule-pack bundle, compiled
// ONCE and reused warm. The swift-linter CLI fast path
// (Lint.File.Single.Classifier) routes a pure-bundle consumer here instead of
// materializing + compiling a per-run eval project, turning a cold ~335–605s
// eval into a ~0.65s warm lint.
//
// This is a SEPARATE package nested in the swift-linter repo (not a target of
// the root Package.swift) so it can be built and cached independently in CI:
//
//   swift build --package-path Runner --product runner   # debug, ~310–560s once
//
// then the dispatcher fast path execs the cached `runner` binary via the
// SWIFT_LINTER_RUNNER environment variable.
//
// All deps are branch:"main" URL packages so the [CI-044] composite cache key
// (engine HEAD + standard rule-pack HEADs) governs freshness; a rule-pack
// commit busts the key → one shared rebuild → instant warm thereafter
// ("A-dynamic": rules always track latest committed main). The local-dev build
// resolves these URLs through ~/.swiftpm/configuration/mirrors.json.
//
// See Research/near-instant-lint-with-external-rule-loading.md (Phase 3).
//
// ===----------------------------------------------------------------------===//

let package = Package(
    name: "standard-runner",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "runner", targets: ["runner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-linter.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-primitives-linter-rules.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "runner",
            dependencies: [
                .product(name: "Linter", package: "swift-linter"),
                // The aggregate `Linter Primitives Rules` product transitively
                // re-exports the institute + universal tiers, so this single
                // product delivers the whole `Lint.Rule.Bundle.primitives` set.
                .product(name: "Linter Primitives Rules", package: "swift-primitives-linter-rules"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    ]
}
