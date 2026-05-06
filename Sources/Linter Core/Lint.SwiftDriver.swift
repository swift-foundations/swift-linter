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
internal import Manifest

/// Detects and evaluates a consumer's `Lint.swift` configuration
/// file via the ``Manifest/Manifest`` subprocess loader.
///
/// Phase 2 v2 (this file) replaces the v1 detection-only stub with
/// a full single-file evaluator: when `Lint.swift` is present at
/// the consumer's package root, the driver compiles + runs it via
/// `swift-manifest`, captures the typed value as
/// ``Lint/Manifest``, and constructs the runtime
/// ``Lint/Configuration`` from the manifest's enabled rule IDs.
///
/// ## Manifest contract
///
/// A consumer's `Lint.swift` MUST declare a file-scope
/// `let manifest: Lint.Manifest = …` value. The driver shim that
/// `swift-manifest` generates serializes this value as JSON and
/// the parent decodes it back via
/// ``Lint/Manifest/deserialize(_:)``.
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
/// If `swift-manifest`'s evaluation fails — manifest absent,
/// driver compile error, runtime trap, JSON decode error — the
/// driver falls back to the v1-default Configuration (every rule
/// in ``Lint/Rule/builtIn`` enabled at default severity). This
/// matches the v1 invariant: the same R5 27-hit count holds even
/// when the v2 evaluation surface is misconfigured.
extension Lint {
    public enum SwiftDriver {}
}

extension Lint.SwiftDriver {
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
    public static func resolveConfiguration(
        consumerPackageRoot: Swift.String
    ) -> Lint.Configuration {
        guard lintSwiftPath(at: consumerPackageRoot) != nil else {
            return _defaultConfiguration()
        }
        do {
            let manifest = try Manifest.load(
                Lint.Manifest.self,
                from: consumerPackageRoot,
                named: "Lint.swift",
                valueName: "manifest",
                dependencies: _manifestDependencies()
            )
            return _configuration(from: manifest)
        } catch {
            return _defaultConfiguration()
        }
    }
}

// MARK: - Internal helpers

extension Lint.SwiftDriver {
    /// Default Configuration: every built-in rule enabled at its
    /// default severity. Identical to v1 detection-only behavior.
    internal static func _defaultConfiguration() -> Lint.Configuration {
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
    internal static func _configuration(from manifest: Lint.Manifest) -> Lint.Configuration {
        let enabled = Set(manifest.enabledRuleIDs)
        return Lint.Configuration(rules: {
            for rule in Lint.Rule.builtIn {
                let ruleID = "\(type(of: rule).id)"
                if enabled.contains(ruleID) {
                    Lint.Rule.Configuration.enable(type(of: rule))
                }
            }
        }, excluded: manifest.excludedPaths)
    }

    /// The dependency set the driver shim compiles against.
    ///
    /// Derived from `SWIFT_LINTER_PATH` (or the workspace default).
    /// The shim needs:
    ///
    ///   - `JSON` (for `.jsonString()` on the typed value),
    ///   - `File_System` (for the `File.write.atomic` output sink),
    ///   - `Linter` (for the ``Lint/Manifest`` type).
    internal static func _manifestDependencies() -> [Manifest.Dependency] {
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
