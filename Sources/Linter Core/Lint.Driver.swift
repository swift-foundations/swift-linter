// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-linter open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-linter project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

internal import Environment
internal import File_System
internal import Manifest_Loader
internal import Manifest_Primitives
internal import Manifest_Resolver

/// Detects and evaluates a consumer's `Lint.swift` configuration
/// file via the ``Manifest_Loader/Manifest/load(_:configuration:)``
/// subprocess loader, then folds parent manifests via
/// ``Manifest_Resolver/Manifest/Resolver/resolve(consumerPackageRoot:manifestFilename:dependencies:defaultConfiguration:buildConfiguration:)``.
///
/// Phase 3a refactor: the chain-resolution machinery (URL fetch,
/// cycle/depth tracking, parent eval, per-process memoization)
/// previously implemented inline now lives in
/// `swift-foundations/swift-manifests` (Manifest Resolver module).
/// `Lint.Driver` is the thin lint-specific wrapper: it determines
/// the manifest path (override-vs-detect), delegates the chain walk
/// to `Manifest.Resolver<Lint.Manifest, Lint.Configuration>`, and
/// catches resolver errors at the wrapper layer to fall back to the
/// default-everything configuration.
///
/// ## Path discovery
///
/// `swift-linter` itself does not know its own filesystem
/// location at runtime. The driver reads the `SWIFT_LINTER_PATH`
/// environment variable to locate the swift-linter source tree
/// (and, by adjacency, sibling foundation packages used in the
/// generated driver shim's deps). The variable MUST be set: when
/// it is unset the driver emits
/// `[swift-linter] error: SWIFT_LINTER_PATH environment variable not set; cannot resolve manifest dependencies`
/// and falls back to the empty default Configuration. There is no
/// hardcoded fallback — every caller is responsible for setting
/// `SWIFT_LINTER_PATH` before invoking the driver.
///
/// ## Failure mode
///
/// If consumer manifest evaluation fails — manifest absent,
/// driver compile error, runtime trap, JSON decode error — the
/// driver falls back to an empty-rules Configuration. Post-Phase-B.1
/// decouple the engine no longer ships built-in rules; the
/// single-file `Lint.swift` fallback path is therefore inert
/// (zero findings) until a consumer-side rule registration
/// mechanism lands. Consumers SHOULD adopt the nested-package
/// shape (`Lint/Package.swift` declaring engine + rule packs)
/// per `Manifest.NestedPackage`. Parent chain failures (cycle,
/// depth, fetch, eval) emit a warning and drop the chain: the
/// consumer-only Configuration is returned.
extension Lint {
    public enum Driver {}
}

extension Lint.Driver {
    /// Detect a nested `Lint/` SwiftPM package at the consumer's
    /// package root and, if present, dispatch the lint run to the
    /// consumer's `Lint` executable via
    /// `swift run --package-path <consumerRoot>/Lint Lint <args>`.
    ///
    /// PoC of the Lint/ nested-package mechanism (architecture cohort
    /// Phase A — `HANDOFF-architecture-poc-lint-nested-package.md`).
    /// Under Option 1 the Lint/ executable IS the linter binary for
    /// the consumer (linking engine + rule packs declared in its
    /// `Lint/Package.swift`); swift-linter (this CLI) becomes a
    /// coordinator that delegates the run when the consumer opts into
    /// the nested-package shape.
    ///
    /// - Returns: `nil` when no nested package is detected — the
    ///   caller should fall through to the single-file `Lint.swift`
    ///   path. Otherwise the dispatched executable's exit code (an
    ///   `Int32`); `0` indicates success, non-zero indicates findings
    ///   or error per the dispatched executable's exit policy.
    public static func dispatchNestedIfPresent(
        consumerPackageRoot: Swift.String,
        arguments: [Swift.String]
    ) -> Swift.Int32? {
        guard Manifest.NestedPackage.detect(at: consumerPackageRoot) else {
            return nil
        }
        do throws(Manifest.NestedPackage.DispatchError) {
            return try Manifest.NestedPackage.dispatch(
                at: consumerPackageRoot,
                arguments: arguments
            )
        } catch {
            print("[swift-linter] error dispatching to Lint/ executable: \(error)")
            return 1
        }
    }

    /// Detects whether a `Lint.swift` exists at the consumer's
    /// package root.
    public static func lintSwiftPath(at consumerPackageRoot: Swift.String) -> Swift.String? {
        let candidate = "\(consumerPackageRoot)/Lint.swift"
        guard let directory = try? File.Directory(validating: consumerPackageRoot) else {
            return nil
        }
        guard let entries = try? directory.entries() else {
            return nil
        }
        for entry in entries where Swift.String(entry.name) == "Lint.swift" {
            return candidate
        }
        return nil
    }

    /// Resolve the configuration for the given consumer root.
    ///
    /// Determines the manifest's `(directory, filename)` from either
    /// `lintSwiftPathOverride` or via detection at
    /// `consumerPackageRoot`, then delegates parent-chain resolution
    /// to ``Manifest_Resolver/Manifest/Resolver/resolve(consumerPackageRoot:manifestFilename:dependencies:defaultConfiguration:buildConfiguration:)``.
    ///
    /// Fall-back paths:
    /// - No `Lint.swift` at consumer root and no override → defaults-everything.
    /// - Override path fails to validate as a `File.Path` → defaults-everything.
    /// - Consumer's `Lint.swift` evaluation fails → defaults-everything (resolver internalizes this).
    /// - Any parent fetch / eval / cycle / depth failure → emit a
    ///   warning, drop the parent chain, return defaults-everything.
    public static func resolveConfiguration(
        consumerPackageRoot: Swift.String,
        lintSwiftPathOverride: Swift.String? = nil
    ) -> Lint.Configuration {
        let manifestDirectory: Swift.String
        let manifestFilename: Swift.String
        if let override = lintSwiftPathOverride {
            do {
                let overridePath = try File.Path(override)
                manifestDirectory = overridePath.parent.map { $0.description } ?? "."
                manifestFilename = overridePath.components.last.map { $0.string } ?? "Lint.swift"
            } catch {
                return defaultConfiguration()
            }
        } else {
            guard lintSwiftPath(at: consumerPackageRoot) != nil else {
                return defaultConfiguration()
            }
            manifestDirectory = consumerPackageRoot
            manifestFilename = "Lint.swift"
        }

        guard let dependencies = manifestDependencies() else {
            return defaultConfiguration()
        }
        do {
            return try Manifest.Resolver<Lint.Manifest, Lint.Configuration>.resolve(
                consumerPackageRoot: manifestDirectory,
                manifestFilename: manifestFilename,
                dependencies: dependencies,
                defaultConfiguration: defaultConfiguration,
                buildConfiguration: { manifest, parent in
                    configuration(from: manifest, parent: parent)
                }
            )
        } catch {
            print("[swift-linter] WARN: parent chain resolution failed: \(error); proceeding with default configuration.")
            return defaultConfiguration()
        }
    }
}

// MARK: - Internal helpers

extension Lint.Driver {
    /// Default Configuration for the single-file `Lint.swift`
    /// fallback path. Post-Phase-B.1 decouple the engine ships no
    /// built-in rules, so this returns an empty-rules Configuration —
    /// the run produces zero findings unless the consumer extends
    /// the engine with rule registration of their own.
    internal static func defaultConfiguration() -> Lint.Configuration {
        Lint.Configuration(rules: { })
    }

    /// Build a runtime Configuration from a parsed manifest.
    ///
    /// Post-Phase-B.1 the engine no longer ships built-in rules, so
    /// the `enabledRuleIDs` / `disabledRuleIDs` lists in the manifest
    /// are silently ignored at this layer; rule registration must
    /// happen at the consumer's `Lint/` executable (which links rule
    /// packs and instantiates `Lint.Configuration` directly).
    ///
    /// `parent` is the next-outer Configuration in the inheritance
    /// chain (or `nil` for the root tier). The returned Configuration
    /// inherits via `Lint.Configuration(inheriting: parent)` and
    /// threads `excluded` paths from the manifest; layered override
    /// semantics are computed by ``Lint/Configuration/effectiveRules()``.
    internal static func configuration(
        from manifest: Lint.Manifest,
        parent: Lint.Configuration?
    ) -> Lint.Configuration {
        Lint.Configuration(
            inheriting: parent,
            rules: { },
            excluded: manifest.excludedPaths.map { $0.description }
        )
    }

    /// The dependency set the driver shim compiles against.
    ///
    /// Derived from `SWIFT_LINTER_PATH`. Returns `nil` when the
    /// variable is unset — `resolveConfiguration` interprets `nil`
    /// as "no manifest evaluation possible" and returns the empty
    /// default Configuration. The shim needs:
    ///
    ///   - `JSON` (for `.jsonString()` on the typed value),
    ///   - `File_System` (for the `File.write.atomic` output sink),
    ///   - `Linter` (for the ``Lint/Manifest`` type).
    internal static func manifestDependencies() -> [Manifest.Dependency]? {
        guard let linterPath = Environment.read("SWIFT_LINTER_PATH") else {
            print("[swift-linter] error: SWIFT_LINTER_PATH environment variable not set; cannot resolve manifest dependencies")
            return nil
        }
        let workspace = linterPath + "/.."
        return [
            Manifest.Dependency(
                path: workspace + "/swift-json",
                name: "swift-json",
                product: "JSON",
                imports: ["JSON"]
            ),
            Manifest.Dependency(
                path: workspace + "/swift-file-system",
                name: "swift-file-system",
                product: "File System",
                imports: ["File_System"]
            ),
            Manifest.Dependency(
                path: linterPath,
                name: "swift-linter",
                product: "Linter",
                imports: ["Linter"]
            )
        ]
    }
}

