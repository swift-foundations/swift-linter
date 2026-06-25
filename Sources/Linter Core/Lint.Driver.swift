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
public import File_System
internal import Linter_Primitives
internal import Manifest_Loader
internal import Manifest_Primitives
internal import Manifest_Resolver

/// Detects and evaluates a consumer's `Lint.swift` configuration
/// file via the ``Manifest_Loader/Manifest/load(_:configuration:)``
/// subprocess loader, then folds parent manifests via
/// ``Manifest_Resolver/Manifest/Resolver/resolve(consumerPackageRoot:filename:dependencies:defaultConfiguration:buildConfiguration:)``.
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

// MARK: - Namespace accessors (Property.View metatype trick)

extension Lint.Driver {
    /// Namespace accessor for dispatch operations. Reads as
    /// `Lint.Driver.dispatch.nested(at: ..., arguments: ...)`.
    @inlinable
    public static var dispatch: Dispatch.Type { Dispatch.self }

    /// Namespace accessor for manifest-detection operations. Reads as
    /// `Lint.Driver.manifest.path(at: ...)`.
    @inlinable
    public static var manifest: Manifest.Type { Manifest.self }
}

// MARK: - Top-level configuration resolution

extension Lint.Driver {
    /// Resolve the configuration for the given consumer root.
    ///
    /// Determines the manifest's `(directory, filename)` from either
    /// `manifestOverride` or via detection at `consumerPackageRoot`,
    /// then delegates parent-chain resolution to
    /// ``Manifest_Resolver/Manifest/Resolver/resolve(consumerPackageRoot:filename:dependencies:defaultConfiguration:buildConfiguration:)``.
    ///
    /// Fall-back paths:
    /// - No `Lint.swift` at consumer root and no override → defaults-everything.
    /// - Override path fails to validate as a `File.Path` → defaults-everything.
    /// - Consumer's `Lint.swift` evaluation fails → defaults-everything (resolver internalizes this).
    /// - Any parent fetch / eval / cycle / depth failure → emit a
    ///   warning, drop the parent chain, return defaults-everything.
    /// - `SWIFT_LINTER_PATH` environment variable is unset → defaults-everything;
    ///   `onMissingLinterPath` is invoked so the CLI can surface the
    ///   missing-env-var diagnostic to stderr.
    ///
    /// Library output discipline: this method does NOT write to stdout
    /// or stderr. The `onMissingLinterPath` closure (default no-op)
    /// gives the CLI binding a hook to emit a stderr diagnostic when
    /// `SWIFT_LINTER_PATH` is unset; non-CLI callers retain the
    /// silent-fallback contract.
    ///
    /// - Parameters:
    ///   - at: Filesystem path to the consumer's package root.
    ///   - manifestOverride: Optional explicit path to the
    ///     consumer's `Lint.swift`; overrides default detection at
    ///     `<consumerPackageRoot>/Lint.swift`.
    ///   - onMissingLinterPath: Optional closure invoked when the
    ///     `SWIFT_LINTER_PATH` environment variable is unset. Default
    ///     is a no-op so library callers retain the silent-fallback
    ///     contract.
    /// F-A2.1 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
    /// path parameters are typed `File.Path`.
    public static func configuration(
        at consumerPackageRoot: File.Path,
        manifestOverride: File.Path? = nil,
        onMissingLinterPath: () -> Void = { }
    ) -> Lint.Configuration {
        let manifestDirectory: Swift.String
        let manifestFilename: Swift.String
        if let override = manifestOverride {
            manifestDirectory = override.parent.map { $0.description } ?? "."
            manifestFilename = override.components.last.map { $0.string } ?? "Lint.swift"
        } else {
            guard Self.manifest.path(at: consumerPackageRoot) != nil else {
                return defaultConfiguration()
            }
            manifestDirectory = consumerPackageRoot.string
            manifestFilename = "Lint.swift"
        }

        guard let dependencies = manifestDependencies() else {
            onMissingLinterPath()
            return defaultConfiguration()
        }
        do throws(Manifest_Resolver.Manifest.Resolver<Lint.Manifest, Lint.Configuration>.Error) {
            return try Manifest_Resolver.Manifest.Resolver<Lint.Manifest, Lint.Configuration>.resolve(
                consumerPackageRoot: manifestDirectory,
                filename: manifestFilename,
                dependencies: dependencies,
                defaultConfiguration: defaultConfiguration,
                buildConfiguration: { manifest, parent in
                    configuration(from: manifest, parent: parent)
                }
            )
        } catch {
            // Library output discipline: silently fall back to the
            // default Configuration on parent-chain failure (cycle,
            // depth, fetch, eval). The fallback is the documented
            // recovery path; consumers needing richer diagnostics
            // should call `Manifest.Resolver.resolve` directly, which
            // throws the typed error.
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
    fileprivate static func defaultConfiguration() -> Lint.Configuration {
        Lint.Configuration { }
    }

    /// Build a runtime Configuration from a parsed manifest.
    ///
    /// Post-Phase-B.1 the engine no longer ships built-in rules, so the
    /// manifest's `enabledRuleIDs` list cannot be mapped to rule TYPES
    /// at this layer — rule registration must happen at the consumer's
    /// `Lint/` executable (which links rule packs and instantiates
    /// `Lint.Configuration` directly with concrete witnesses). The
    /// manifest's `disabledRuleIDs` list, however, is threaded
    /// through to ``Lint/Configuration/Rules/disabled``: the engine
    /// applies the rule-wide disable wholesale at
    /// ``Lint/Configuration/Rules/effective``, dropping any rule
    /// whose ID matches regardless of which layer registered it.
    /// Per-line `// swift-linter:disable:next <id>` directives compose
    /// on top of this rule-wide disable per decision 2026-05-11.
    ///
    /// `parent` is the next-outer Configuration in the inheritance
    /// chain (or `nil` for the root tier). The returned Configuration
    /// inherits via `Lint.Configuration(inheriting: parent)` and
    /// threads `excluded` paths plus `disabledRuleIDs` from the
    /// manifest; layered override semantics are computed by
    /// ``Lint/Configuration/Rules/effective``.
    internal static func configuration(
        from manifest: Lint.Manifest,
        parent: Lint.Configuration?
    ) -> Lint.Configuration {
        Lint.Configuration(
            inheriting: parent,
            excluded: manifest.excluded.map(Lint.Filter.Prefix.init),
            disabled: manifest.rules.disabled
        ) { }
    }

    /// The dependency set the driver shim compiles against.
    ///
    /// Derived from `SWIFT_LINTER_PATH`. Returns `nil` when the
    /// variable is unset — `configuration(at:)` interprets `nil`
    /// as "no manifest evaluation possible" and returns the empty
    /// default Configuration. The shim needs:
    ///
    ///   - `JSON` (for `.jsonString()` on the typed value),
    ///   - `File_System` (for the `File.write.atomic` output sink),
    ///   - `Linter` (for the ``Lint/Manifest`` type).
    fileprivate static func manifestDependencies() -> [Manifest_Primitives.Manifest.Dependency]? {
        // Library output discipline: silently return nil when
        // SWIFT_LINTER_PATH is unset. The CLI is responsible for
        // validating preconditions and surfacing the env-var error
        // to the user before invoking the Driver.
        guard let linterPath = Environment.read("SWIFT_LINTER_PATH") else {
            return nil
        }
        // F-A1.13 (audit `2026-05-12-typed-primitive-adoption-audit.md`):
        // sibling code path to `Lint.File.Single.resolveParentChain`
        // F-A1.11. `Paths.Path.parent` owns dot-segment semantics —
        // the prior `linterPath + "/.."` produces a path with an
        // unresolved `..` segment, while `.parent` resolves to the
        // workspace directory directly. Silent-fallback `nil` on
        // parse failure mirrors the documented contract.
        let linter: File.Path
        do throws(Paths.Path.Error) {
            linter = try File.Path(linterPath)
        } catch {
            return nil
        }
        guard let workspace: File.Path = linter.parent else {
            return nil
        }
        return [
            Manifest_Primitives.Manifest.Dependency(
                path: (workspace / "swift-json").string,
                name: "swift-json",
                product: "JSON",
                imports: ["JSON"]
            ),
            Manifest_Primitives.Manifest.Dependency(
                path: (workspace / "swift-file-system").string,
                name: "swift-file-system",
                product: "File System",
                imports: ["File_System"]
            ),
            Manifest_Primitives.Manifest.Dependency(
                path: linterPath,
                name: "swift-linter",
                product: "Linter",
                imports: ["Linter"]
            )
        ]
    }
}
