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
    /// Library output discipline: this helper does NOT write to stdout
    /// or stderr. Dispatch errors are surfaced via the optional
    /// `onDispatchError` closure; the default no-op preserves the
    /// silent-fallback behavior for non-CLI callers. The CLI binding
    /// supplies a closure that emits to `Terminal.Stream.stderr.write`
    /// so end users see a typed-error diagnostic instead of a bare
    /// non-zero exit.
    ///
    /// - Parameters:
    ///   - consumerPackageRoot: Filesystem path to the consumer's
    ///     package root (the directory containing the consumer's
    ///     `Package.swift`).
    ///   - arguments: Arguments forwarded to the dispatched `Lint`
    ///     executable.
    ///   - onDispatchError: Optional closure invoked when
    ///     ``Manifest_Resolver/Manifest/NestedPackage/dispatch(at:arguments:)``
    ///     throws. Receives the error's textual description; CLI
    ///     callers translate this to a stderr diagnostic. Defaults to
    ///     a no-op so library callers retain the silent-fallback
    ///     contract.
    /// - Returns: `nil` when no nested package is detected — the
    ///   caller should fall through to the single-file `Lint.swift`
    ///   path. Otherwise the dispatched executable's exit code (an
    ///   `Int32`); `0` indicates success, non-zero indicates findings
    ///   or error per the dispatched executable's exit policy. When
    ///   the dispatch itself fails (spawn error), returns `1` after
    ///   invoking `onDispatchError`.
    public static func dispatchNestedIfPresent(
        consumerPackageRoot: Swift.String,
        arguments: [Swift.String],
        onDispatchError: (Swift.String) -> Void = { _ in }
    ) -> Swift.Int32? {
        guard Manifest.NestedPackage.detect(at: consumerPackageRoot) else {
            return nil
        }
        do throws(Manifest.NestedPackage.Error) {
            return try Manifest.NestedPackage.dispatch(
                at: consumerPackageRoot,
                arguments: arguments
            )
        } catch {
            onDispatchError("\(error)")
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
    /// to ``Manifest_Resolver/Manifest/Resolver/resolve(consumerPackageRoot:filename:dependencies:defaultConfiguration:buildConfiguration:)``.
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
    ///   - consumerPackageRoot: Filesystem path to the consumer's
    ///     package root.
    ///   - lintSwiftPathOverride: Optional explicit path to the
    ///     consumer's `Lint.swift`; overrides default detection at
    ///     `<consumerPackageRoot>/Lint.swift`.
    ///   - onMissingLinterPath: Optional closure invoked when the
    ///     `SWIFT_LINTER_PATH` environment variable is unset. Default
    ///     is a no-op so library callers retain the silent-fallback
    ///     contract.
    public static func resolveConfiguration(
        consumerPackageRoot: Swift.String,
        lintSwiftPathOverride: Swift.String? = nil,
        onMissingLinterPath: () -> Void = { }
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
            onMissingLinterPath()
            return defaultConfiguration()
        }
        do {
            return try Manifest.Resolver<Lint.Manifest, Lint.Configuration>.resolve(
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
    internal static func defaultConfiguration() -> Lint.Configuration {
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
    /// through to ``Lint/Configuration/disabledRuleIDs``: the engine
    /// applies the rule-wide disable wholesale at
    /// ``Lint/Configuration/effectiveRules()``, dropping any rule
    /// whose ID matches regardless of which layer registered it.
    /// Per-line `// swift-linter:disable:next <id>` directives compose
    /// on top of this rule-wide disable per decision 2026-05-11.
    ///
    /// `parent` is the next-outer Configuration in the inheritance
    /// chain (or `nil` for the root tier). The returned Configuration
    /// inherits via `Lint.Configuration(inheriting: parent)` and
    /// threads `excluded` paths plus `disabledRuleIDs` from the
    /// manifest; layered override semantics are computed by
    /// ``Lint/Configuration/effectiveRules()``.
    internal static func configuration(
        from manifest: Lint.Manifest,
        parent: Lint.Configuration?
    ) -> Lint.Configuration {
        Lint.Configuration(
            inheriting: parent,
            excluded: manifest.excludedPaths.map(Lint.Filter.Prefix.init),
            disabledRuleIDs: manifest.disabledRuleIDs
        ) { }
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
        // Library output discipline: silently return nil when
        // SWIFT_LINTER_PATH is unset. The CLI is responsible for
        // validating preconditions and surfacing the env-var error
        // to the user before invoking the Driver.
        guard let linterPath = Environment.read("SWIFT_LINTER_PATH") else {
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

