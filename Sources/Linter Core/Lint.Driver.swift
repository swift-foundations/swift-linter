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
internal import URI_Standard

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
/// generated driver shim's deps). When the variable is unset the
/// driver falls back to the workspace-relative default
/// `/Users/coen/Developer/swift-foundations/swift-linter` so that
/// local development verifies without per-shell setup. Production
/// deployments SHOULD set `SWIFT_LINTER_PATH` explicitly.
///
/// ## Failure mode
///
/// If consumer manifest evaluation fails — manifest absent,
/// driver compile error, runtime trap, JSON decode error — the
/// driver falls back to the v1-default Configuration (every rule
/// in ``Lint/Rule/builtIn`` enabled at default severity). Parent
/// chain failures (cycle, depth, fetch, eval) emit a warning and
/// drop the chain: the consumer-only Configuration is returned.
extension Lint {
    public enum Driver {}
}

extension Lint.Driver {
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

        do {
            return try Manifest.Resolver<Lint.Manifest, Lint.Configuration>.resolve(
                consumerPackageRoot: manifestDirectory,
                manifestFilename: manifestFilename,
                dependencies: manifestDependencies(),
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
    /// Default Configuration: every built-in rule enabled at its
    /// default severity. Identical to v1 detection-only behavior.
    internal static func defaultConfiguration() -> Lint.Configuration {
        Lint.Configuration(rules: {
            for rule in Lint.Rule.builtIn {
                Lint.Rule.Configuration.enable(type(of: rule))
            }
        })
    }

    /// Build a runtime Configuration from a parsed manifest by
    /// looking up each rule ID in ``Lint/Rule/builtIn``. Unknown
    /// rule IDs are silently ignored at v2 (rule registration is
    /// not yet pluggable from the manifest); known IDs are enabled
    /// at the rule's default severity.
    ///
    /// `parent` is the next-outer Configuration in the inheritance
    /// chain (or `nil` for the root tier). The returned Configuration
    /// inherits via `Lint.Configuration(inheriting: parent)`; layered
    /// override semantics are computed by ``Lint/Configuration/effectiveRules()``.
    ///
    /// Each ID in `disabledRuleIDs` becomes a
    /// `Lint.Rule.Configuration.disable(...)` entry at this layer,
    /// overriding any parent enable for the same rule TYPE per
    /// `effectiveRules()`'s "later layer wins" rule.
    internal static func configuration(
        from manifest: Lint.Manifest,
        parent: Lint.Configuration?
    ) -> Lint.Configuration {
        let enabled = Set(manifest.enabledRuleIDs)
        let disabled = Set(manifest.disabledRuleIDs)
        return Lint.Configuration(
            inheriting: parent,
            rules: {
                for rule in Lint.Rule.builtIn {
                    let ruleID = type(of: rule).id
                    if disabled.contains(ruleID) {
                        Lint.Rule.Configuration.disable(type(of: rule))
                    } else if enabled.contains(ruleID) {
                        Lint.Rule.Configuration.enable(type(of: rule))
                    }
                }
            },
            excluded: manifest.excludedPaths.map { $0.description }
        )
    }

    /// The dependency set the driver shim compiles against.
    ///
    /// Derived from `SWIFT_LINTER_PATH` (or the workspace default).
    /// The shim needs:
    ///
    ///   - `JSON` (for `.jsonString()` on the typed value),
    ///   - `File_System` (for the `File.write.atomic` output sink),
    ///   - `Linter` (for the ``Lint/Manifest`` type).
    internal static func manifestDependencies() -> [Manifest.Dependency] {
        let linterPath = Environment.read("SWIFT_LINTER_PATH")
            ?? "/Users/coen/Developer/swift-foundations/swift-linter"
        let workspace = linterPath + "/.."
        return [
            Manifest.Dependency(
                path: workspace + "/swift-json",
                packageName: "swift-json",
                product: "JSON",
                imports: ["JSON"]
            ),
            Manifest.Dependency(
                path: workspace + "/swift-file-system",
                packageName: "swift-file-system",
                product: "File System",
                imports: ["File_System"]
            ),
            Manifest.Dependency(
                path: linterPath,
                packageName: "swift-linter",
                product: "Linter",
                imports: ["Linter"]
            )
        ]
    }
}

// MARK: - Phase 2.5 ecosystem-promotion candidates

extension Lint.Driver {
    /// Filename-safe form of an arbitrary string (alphanumerics +
    /// `_-.` retained, everything else mapped to `_`). Deterministic;
    /// same input → same output within and across processes.
    ///
    /// TODO (Phase 2.5b ecosystem-promotion): replace with
    /// `Path.sanitized(from:)` from `swift-path-primitives` once that
    /// ecosystem API lands. The Manifest Resolver carries its own
    /// internal copy of this logic; this surface is retained here
    /// only because tests assert against it; Phase 2.5b removes it
    /// once the ecosystem replacement lands and the tests retarget.
    internal static func sanitizeForPath(_ string: Swift.String) -> Swift.String {
        var sanitized = ""
        for character in string {
            if character.isLetter || character.isNumber
                || character == "_" || character == "-" || character == "."
            {
                sanitized.append(character)
            } else {
                sanitized.append("_")
            }
        }
        return sanitized
    }

    /// Deterministic temp-file path for a given `URI`. Sanitizes the
    /// URI's full string value via ``sanitizeForPath(_:)``.
    ///
    /// TODO (Phase 2.5b ecosystem-promotion): replace with
    /// `File.Path.Temporary.deterministic(prefix:key:suffix:)` from
    /// `swift-file-system` once that ecosystem API lands. The
    /// Manifest Resolver no longer consumes this surface; retained
    /// only for the existing tests, which Phase 2.5b retargets.
    internal static func tempPathFor(url uri: URI) -> Swift.String {
        "/tmp/swift-linter-fetch-\(sanitizeForPath(uri.value)).tmp"
    }
}
