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
internal import Manifest_Executable
internal import Manifest_Primitives
internal import Manifest_Resolver
internal import Package_Primitives
internal import SPM_Standard
internal import SwiftSyntax
internal import URI_Standard_Library_Integration

extension Lint.File.Single {
    /// The eval fallback: materialize a temporary SwiftPM project around the
    /// consumer's `Lint.swift`, compile it (engine + declared rule packs), and
    /// spawn it.
    ///
    /// Taken whenever the prebuilt runner cannot faithfully reproduce
    /// the consumer's rule configuration — inline/custom rules, a non-baked
    /// bundle, a `// parent:` chain, or an unprovisioned runner. Report format
    /// is channel-borne and is therefore identical on this path and the
    /// prebuilt path. The compiled executable IS the linter binary for the
    /// consumer; its stdout is the authoritative diagnostic stream.
    ///
    /// This is the path that preserves fully-dynamic, consumer-declared rule
    /// loading: the consumer's own `.package(...)` dependencies are extracted
    /// and compiled fresh, exactly as authored.
    public enum Eval: Swift.Sendable {}
}

extension Lint.File.Single.Eval {
    /// The published engine repository URL the materialized eval project
    /// references when no local-dev `SWIFT_LINTER_PATH` override is set.
    ///
    /// Phase 0 of `Research/near-instant-lint-with-external-rule-loading.md`: a
    /// standalone CLI binary has no engine source tree, so the eval
    /// `Package.swift` references the engine by URL pin instead of a `.path(...)`
    /// dependency. `SWIFT_LINTER_PATH`, when set, still wins (the local-dev inner
    /// loop builds against the engine HEAD). `private` — an internal eval-pipeline
    /// constant, not consumer-facing API.
    ///
    /// Typed as ``RFC_3986/URI`` via its `ExpressibleByStringLiteral` conformance:
    /// a hardcoded, source-reviewed constant whose validity is guaranteed at
    /// compile time, so a malformed literal traps at load (an authoring defect)
    /// rather than threading a runtime `URIError` no caller could recover from.
    private static let engineDependencyURL: URI =
        "https://github.com/swift-foundations/swift-linter.git"

    /// The git branch the materialized eval tracks for the engine.
    ///
    /// Used when no `SWIFT_LINTER_BRANCH` override is set. `main` matches the
    /// ecosystem `branch: "main"` dependency convention (active development; no
    /// semver/release tags) — tag-free by design. `private`, as above.
    private static let engineDependencyBranch: Swift.String = "main"

    /// Materialize + spawn the eval project for a Shape-γ consumer, returning
    /// the compiled executable's exit code.
    ///
    /// Pipeline: extract the consumer's `.package(...)` dependencies from the
    /// already-parsed tree → resolve the `// parent:` chain (write the folded
    /// manifest via the parent ``Channel``) → resolve the engine dependency
    /// (`SWIFT_LINTER_PATH` `.path` override, else the branch-pinned URL) →
    /// build a ``Manifest/Executable/Configuration`` → hand off to
    /// ``Manifest/Executable/dispatch(configuration:)`` (which renders the
    /// `Package.swift`, copies `Lint.swift` as `main.swift`, and spawns
    /// `swift run … Lint <arguments>`).
    internal static func run(
        consumerPackageRoot: File.Path,
        consumerLintSwiftPath: File.Path,
        source: Swift.String,
        parsed: SourceFileSyntax,
        arguments: [Swift.String],
        nonce: Swift.String
    ) throws(Lint.File.Single.Error) -> Swift.Int32 {
        // Extract `Lint.run(dependencies:)` clauses from the already-parsed
        // tree — only the eval path materializes a project and so needs them.
        let extractedDependencies: [Package.Dependency] = try Lint.File.Single.Extractor
            .dependencies(
                parsed: parsed,
                sourcePath: consumerLintSwiftPath,
                consumerPackageRoot: consumerPackageRoot
            )

        // Resolve the parent chain (writes the folded `Lint.Manifest` via the
        // parent ``Channel`` and returns its path). Runs BEFORE
        // Manifest.Executable.dispatch materializes `.swift-lint/eval/` over the
        // same `.swift-lint/` parent directory.
        let parentManifestPath: File.Path? = try Self.resolveParentChain(
            consumerSource: source,
            consumerPackageRoot: consumerPackageRoot,
            nonce: nonce
        )

        // Resolve the engine dependency the generated Package.swift references.
        //   (a) SWIFT_LINTER_PATH set → local-dev `.path(...)` on the engine
        //       source tree (HEAD) — preserves the inner-loop workflow.
        //   (b) otherwise → branch-pinned `.url(..., branch:)` on the engine
        //       `Linter` library (tag-free), so a standalone CLI binary (no
        //       engine source tree) can dispatch the eval.
        let linterDependency: Package.Dependency
        if let rawPath: Swift.String = Environment.read("SWIFT_LINTER_PATH") {
            do throws(Paths.Path.Error) {
                _ = try Paths.Path(rawPath)
            } catch {
                throw .materializationFailed(
                    reason: "SWIFT_LINTER_PATH `\(rawPath)` is not a valid path: \(error)"
                )
            }
            linterDependency = Package.Dependency(
                source: .path(rawPath),
                name: "swift-linter",
                products: ["Linter"]
            )
        } else {
            linterDependency = Self.publishedEngineDependency()
        }
        let dependencies: [Package.Dependency] = [linterDependency] + extractedDependencies

        // Preserve the complete coordinator environment, including output
        // format, exit policy, and fix channels, then add the eval-specific
        // parent manifest when present.
        let environment: [Swift.String: Swift.String] = Self.environment(
            inheriting: Environment.Snapshot.current(),
            parent: parentManifestPath
        )

        // Stamp the state directory self-ignoring before the eval project is
        // materialized into it: `dispatch` creates `evalRoot` on its own, and a
        // run that never wrote a channel manifest would otherwise leave the
        // thousands of eval files untracked in the consumer's worktree.
        let stateRoot: File.Path
        do throws(Lint.File.Single.State.Error) {
            stateRoot = try Lint.File.Single.State.create(consumerPackageRoot: consumerPackageRoot)
        } catch {
            throw .materializationFailed(reason: "create state directory: \(error)")
        }
        let evalRoot: File.Path = stateRoot / "eval"

        // Invalidate any resolution state a PRIOR materialization of this
        // same eval project left behind. Every dependency below is declared
        // `branch: "main"` (tag-free by design — see `publishedEngineDependency()`
        // and `engineDependencyBranch`), but a bare `swift run` does NOT
        // re-resolve a branch-tracked dependency once a lockfile already
        // pins it: SwiftPM only advances that pin on an explicit
        // `swift package update` or when no lockfile is present. Because
        // `.swift-lint/eval/` is long-lived scratch state — materialized
        // once per consumer, then reused indefinitely by every later
        // dispatch (`Lint.File.Single.State`) — a consumer whose eval
        // project predates an engine improvement (a new reporter format, a
        // rule-pack update, a bug fix) keeps silently compiling and running
        // that STALE engine on every subsequent run, even though the
        // swift-linter CLI doing the dispatching is fully current. Deleting
        // the resolution state before each dispatch costs one fresh
        // resolution — negligible next to the compile this path already
        // pays on every call (documented elsewhere as the eval fallback's
        // ~155s cold floor) — and guarantees the eval always builds against
        // the CURRENT `main` its dependencies declare.
        try Self.invalidateStaleResolution(evalRoot: evalRoot)
        let configuration = Manifest.Executable.Configuration(
            consumerPackageRoot: consumerPackageRoot,
            consumerSourcePath: consumerLintSwiftPath,
            evalRoot: evalRoot,
            executableName: "Lint",
            dependencies: dependencies,
            platforms: [".macOS(.v26)"],
            swiftLanguageModes: [".v6"],
            ecosystemSettings: [
                ".enableUpcomingFeature(\"ExistentialAny\")",
                ".enableUpcomingFeature(\"InternalImportsByDefault\")",
                ".enableUpcomingFeature(\"MemberImportVisibility\")",
                ".enableUpcomingFeature(\"NonisolatedNonsendingByDefault\")",
            ],
            arguments: arguments,
            environment: environment,
            toolsVersion: "6.3.1"
        )

        // Hand off; map errors at the boundary so Lint.File.Single.Error stays
        // the consumer-facing throw shape.
        do throws(Manifest.Executable.Error) {
            return try Manifest.Executable.dispatch(configuration: configuration)
        } catch {
            switch error {
            case .readFailed(let path, let description):
                throw .readFailed(path: path, description: description)

            case .materializationFailed(let reason):
                throw .materializationFailed(reason: reason)

            case .spawnFailed(let consumerPackageRoot, let description):
                throw .spawnFailed(
                    consumerPackageRoot: consumerPackageRoot,
                    description: description
                )
            }
        }
    }

    /// Remove a prior materialization's resolution state from `evalRoot`, if
    /// any exists: `Package.resolved` AND SwiftPM's own
    /// `.build/workspace-state.json`.
    ///
    /// `.swift-lint/eval/` is reused across every dispatch for a given
    /// consumer (`Lint.File.Single.State`); SwiftPM only advances a
    /// `branch:`-tracked dependency's pin when no lockfile is present or on
    /// an explicit `swift package update` — a bare `swift run` against an
    /// existing lockfile keeps the ORIGINAL resolution forever. Every
    /// dependency this eval declares (the engine itself, chief among them —
    /// see ``publishedEngineDependency()``) is branch-tracked and tag-free
    /// by design specifically so the eval always reflects `main`; without
    /// this call, a consumer's eval project silently freezes at whatever
    /// commit was current the first time it was ever materialized,
    /// including engine fixes and reporter capabilities that landed after
    /// that point.
    ///
    /// Deleting `Package.resolved` alone is NOT sufficient: SwiftPM's build
    /// system separately caches the resolved dependency graph in
    /// `.build/workspace-state.json`, and restores `Package.resolved` from
    /// that cache rather than re-resolving when the lockfile alone is
    /// missing. Both must go for a dispatch to see a genuinely fresh
    /// resolution. The rest of `.build` (compiled object files, module
    /// caches) is left untouched — SwiftPM's incremental build correctly
    /// recompiles only what a newly-fetched checkout actually changed, so
    /// this keeps most of the eval path's compile-cache benefit while still
    /// guaranteeing the dependency graph itself is never stale.
    ///
    /// Best-effort and idempotent: absence of either file (first-ever
    /// materialization) is the common case, not a failure.
    internal static func invalidateStaleResolution(
        evalRoot: File.Path
    ) throws(Lint.File.Single.Error) {
        let staleStatePaths: [File.Path] = [
            evalRoot / "Package.resolved",
            evalRoot / ".build" / "workspace-state.json",
        ]
        for path in staleStatePaths {
            do throws(File.System.Delete.Error) {
                try File(path).delete.ifExists()
            } catch {
                throw .materializationFailed(
                    reason: "invalidate stale eval resolution at \(path): \(error)"
                )
            }
        }
    }

    /// Build the complete environment supplied to the eval executable.
    ///
    /// The inherited snapshot carries coordinator-owned channels unchanged;
    /// this boundary owns only the optional parent-manifest overlay.
    internal static func environment(
        inheriting snapshot: Environment.Snapshot,
        parent manifest: File.Path?
    ) -> [Swift.String: Swift.String] {
        var environment = snapshot
        if let manifest {
            environment.values[Lint.File.Single.Channel.parent.variable] = manifest.string
        }
        return environment.values
    }

    /// Build the branch-pinned URL engine dependency (override the branch via
    /// `SWIFT_LINTER_BRANCH`).
    ///
    /// Tag-free; tracks ``engineDependencyBranch``.
    private static func publishedEngineDependency() -> Package.Dependency {
        let branch: Swift.String =
            Environment.read("SWIFT_LINTER_BRANCH") ?? Self.engineDependencyBranch
        return Package.Dependency(
            source: .url(Self.engineDependencyURL, branch: branch),
            name: "swift-linter",
            products: ["Linter"]
        )
    }

    /// Walk the `// parent:` chain in `consumerSource` and write the folded
    /// `Lint.Manifest` via the parent ``Channel``.
    ///
    /// Returns the path when a chain
    /// is present, `nil` when no parent directive is found.
    ///
    /// Parent eval uses the same dependency set as
    /// ``Lint/Driver/configuration(at:manifestOverride:onMissingLinterPath:)`` —
    /// JSON, File_System, Linter — resolved against `SWIFT_LINTER_PATH`. When
    /// the env var is unset the resolver cannot evaluate parents; the method
    /// returns `nil` and lint proceeds without parent inheritance.
    private static func resolveParentChain(
        consumerSource: Swift.String,
        consumerPackageRoot: File.Path,
        nonce: Swift.String
    ) throws(Lint.File.Single.Error) -> File.Path? {
        guard let linterPath: Swift.String = Environment.read("SWIFT_LINTER_PATH") else {
            return nil
        }
        let linter: File.Path
        do throws(Paths.Path.Error) {
            linter = try File.Path(linterPath)
        } catch {
            return nil
        }
        guard let workspace: File.Path = linter.parent else {
            return nil
        }
        let parentDependencies: [Manifest.Dependency] = [
            Manifest.Dependency(
                path: (workspace / "swift-json").string,
                name: "swift-json",
                product: "JSON",
                imports: ["JSON"]
            ),
            Manifest.Dependency(
                path: (workspace / "swift-file-system").string,
                name: "swift-file-system",
                product: "File System",
                imports: ["File_System"]
            ),
            Manifest.Dependency(
                path: linterPath,
                name: "swift-linter",
                product: "Linter",
                imports: ["Linter"]
            ),
        ]
        let parentChain: [Lint.Manifest]
        do throws(Manifest.Resolver<Lint.Manifest, Lint.Manifest>.Error) {
            parentChain = try Manifest.Resolver<Lint.Manifest, Lint.Manifest>.walkParents(
                from: consumerSource,
                filename: "Lint.swift",
                dependencies: parentDependencies
            )
        } catch {
            // Parent chain failure — silent fall-through to no inheritance. The
            // dispatch can still proceed; the consumer's own activations are
            // unaffected.
            return nil
        }
        guard !parentChain.isEmpty else {
            return nil
        }
        let folded: Lint.Manifest = Self.foldParents(parentChain)
        do throws(Lint.File.Single.Channel.Error) {
            return try Lint.File.Single.Channel.parent.write(
                folded,
                consumerPackageRoot: consumerPackageRoot,
                nonce: nonce
            )
        } catch {
            throw .materializationFailed(reason: "write parent manifest: \(error)")
        }
    }

    /// Fold a parent-first chain of `Lint.Manifest` values into a single
    /// effective Manifest.
    ///
    /// Order is preserved (root-most first, closest-to-
    /// consumer last); the consumer's ``Lint/Configuration/Rules/effective``
    /// handles dedup and override semantics (later wins per rule ID).
    private static func foldParents(_ chain: [Lint.Manifest]) -> Lint.Manifest {
        var enabled: Set<Lint.Rule.ID> = []
        var disabled: Set<Lint.Rule.ID> = []
        var excluded: [File.Path] = []
        for parent in chain {
            enabled.formUnion(parent.rules.enabled)
            disabled.formUnion(parent.rules.disabled)
            excluded.append(contentsOf: parent.excluded)
        }
        return Lint.Manifest(
            enabled: enabled,
            disabled: disabled,
            excluded: excluded
        )
    }
}
