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
internal import Manifest_Executable
internal import Manifest_Loader
internal import Manifest_Primitives
internal import Manifest_Resolver
internal import Package_Primitives
internal import Process
internal import SPM_Standard
internal import SwiftParser
internal import SwiftSyntax
internal import Version_Primitives

/// Detection + dispatch for the unified single-file consumer manifest
/// shape (research recommendation Shape γ; see
/// `swift-institute/Research/2026-05-12-swift-linter-unified-consumer-manifest.md`).
///
/// A Shape-γ consumer places a `Lint.swift` at the package root with a
/// `// swift-linter-tools-version: 0.1` magic-comment header. The file
/// declares BOTH the SwiftPM dependencies the linter must fetch (rule
/// packs, SwiftSyntax) AND the rule activations to apply, in one
/// self-contained Swift literal:
///
/// ```swift
/// // swift-linter-tools-version: 0.1
/// import Linter
/// import Linter_Primitives_Rules
///
/// Lint.run(dependencies: [
///     .package(path: "../../swift-primitives-linter-rules",
///              products: ["Linter Primitives Rules"]),
/// ]) {
///     Lint.Rule.Bundle.primitives
/// }
/// ```
///
/// Detection (``detect(at:)``) confirms the file's presence at the
/// consumer root and the magic-comment header. Dispatch
/// (``dispatch(at:arguments:)``) parses the file via SwiftSyntax to
/// extract the `.package(...)` declarations, materializes a temporary
/// eval project at `<consumerRoot>/.swift-lint/eval/`, copies
/// `Lint.swift` as the eval target's `main.swift`, and spawns
/// `swift run --package-path <eval> Lint -- <args>`. The dispatched
/// executable IS the linter binary for the consumer — its stdout is
/// the authoritative diagnostic stream.
///
/// This dispatch path is intentionally additive. The existing
/// nested-package (`Lint/Package.swift`) and inert legacy single-file
/// (`let manifest: Lint.Manifest`) paths are unchanged; callers
/// detect in priority order: single-file Shape γ → nested-package →
/// legacy inert.
extension Lint.File {
    public enum Single: Swift.Sendable {}
}

extension Lint.File.Single {
    /// The magic-comment header that identifies a Shape-γ
    /// `Lint.swift`.
    ///
    /// Matched case-sensitively in the file's first leading-trivia
    /// block. Files without this header are NOT treated as Shape-γ —
    /// callers fall through to the next detection path.
    public static let header: Swift.String = "swift-linter-tools-version:"

    /// The published engine repository URL the materialized eval project
    /// references when no local-dev `SWIFT_LINTER_PATH` override is set.
    ///
    /// Phase 0 of
    /// `Research/near-instant-lint-with-external-rule-loading.md`: a
    /// standalone CLI binary has no engine source tree, so the eval
    /// `Package.swift` references the engine by URL pin instead of a
    /// `.path(...)` dependency. `SWIFT_LINTER_PATH`, when set, still wins
    /// (the local-dev inner loop builds against the engine HEAD).
    public static let engineDependencyURL: Swift.String =
        "https://github.com/swift-foundations/swift-linter.git"

    /// The git branch the materialized eval tracks for the engine when no
    /// `SWIFT_LINTER_BRANCH` override is set.
    ///
    /// `main` matches the ecosystem `branch: "main"` dependency convention
    /// (active development; no semver/release tags). Tag-free by design — the
    /// engine is referenced by branch, not by a release tag, so a prebuilt
    /// CLI dispatches the eval without implying a published release.
    public static let engineDependencyBranch: Swift.String = "main"

    /// Build the engine dependency the generated eval `Package.swift`
    /// references when no `SWIFT_LINTER_PATH` override is set: a branch-pinned
    /// URL dependency on the `Linter` library product.
    ///
    /// Tag-free — tracks ``engineDependencyBranch`` (override via the
    /// `SWIFT_LINTER_BRANCH` environment variable), matching the ecosystem
    /// `branch: "main"` convention. Phase 0 of
    /// `Research/near-instant-lint-with-external-rule-loading.md`.
    fileprivate static func publishedEngineDependency()
        throws(Lint.File.Single.Error) -> Package.Dependency
    {
        let branch: Swift.String =
            Environment.read("SWIFT_LINTER_BRANCH") ?? Self.engineDependencyBranch
        let url: URI
        do throws(URIError) {
            url = try URI(Self.engineDependencyURL)
        } catch {
            throw .materializationFailed(
                reason: "invalid engine dependency URL `\(Self.engineDependencyURL)`: \(error)"
            )
        }
        return Package.Dependency(
            source: .url(url, branch: branch),
            name: "swift-linter",
            products: ["Linter"]
        )
    }

    /// Canonicalize a CLI-supplied consumer-root path to its absolute
    /// form. When the path is `"."` or empty (the canonical
    /// `swift-linter .` invocation), substitutes the current working
    /// directory yielded by `currentWorkingDirectory()`; otherwise
    /// returns the path unchanged.
    ///
    /// SwiftPM rejects the literal `"."` as a package name in the
    /// materialized eval project (`unknown package '.'`), so the CLI
    /// must resolve `"."` to an absolute path before calling
    /// ``dispatch(at:arguments:)``. The cwd-yielding closure is
    /// injected so this helper stays platform-neutral and unit-testable
    /// without pulling kernel-tier dependencies into Linter Core; the
    /// CLI binds it to `Kernel.Directory.Working.current()` per the
    /// platform skill's L3-unifier composition discipline.
    @inlinable
    public static func canonicalize(
        consumerRoot: Swift.String,
        currentWorkingDirectory: () -> Swift.String?
    ) -> Swift.String {
        if consumerRoot.isEmpty || consumerRoot == "." {
            return currentWorkingDirectory() ?? consumerRoot
        }
        return consumerRoot
    }

    /// Detect whether `<consumerPackageRoot>/Lint.swift` exists AND
    /// carries the Shape-γ magic-comment header.
    ///
    /// Returns the path to the file when detection succeeds, `nil`
    /// otherwise. The magic-comment check is line-by-line over the
    /// file's first 30 lines (sufficient for the institute's
    /// canonical scaffolds; SE-0152 SwiftPM places the analogous
    /// `swift-tools-version:` directive at line 1).
    ///
    /// F-A2.3 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
    /// `consumerPackageRoot` is typed `File.Path`; the returned
    /// candidate path is also typed.
    public static func detect(
        at consumerPackageRoot: File.Path
    ) -> File.Path? {
        let candidate: File.Path = consumerPackageRoot / "Lint.swift"
        let directory: File.Directory
        do throws(Paths.Path.Error) {
            directory = try File.Directory(validating: consumerPackageRoot.string)
        } catch {
            // Silent-fallback contract: invalid directory path falls
            // through to "no Shape-γ manifest detected." The caller
            // moves on to nested-package detection.
            return nil
        }
        let entries: [File.Directory.Entry]
        do throws(File.Directory.Contents.Error) {
            entries = try directory.entries()
        } catch {
            return nil
        }
        var found = false
        for entry in entries where Swift.String(entry.name) == "Lint.swift" {
            found = true
            break
        }
        guard found else { return nil }
        let source: Swift.String
        do throws(File.System.Read.Full.Error) {
            source = try Self.contents(of: candidate)
        } catch {
            return nil
        }
        return Self.hasMagicComment(in: source) ? candidate : nil
    }

    /// Scan the leading 30 lines of `source` for the
    /// ``header`` substring and parse the typed
    /// ``Version/Tools`` value that follows it.
    ///
    /// Returns `nil` when no magic-comment line is present, OR when
    /// the version following the header fails to parse as
    /// ``Version/Tools``. The boolean ``hasMagicComment(in:)``
    /// wrapper delegates here for the existing detection contract.
    fileprivate static func parseMagicCommentToolsVersion(
        in source: Swift.String
    ) -> Version.Tools? {
        var lineCount = 0
        for line in source.split(separator: "\n", maxSplits: 30, omittingEmptySubsequences: false) {
            if line.contains(Self.header) {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                var versionSlice = parts[1]
                while let first = versionSlice.first, first == " " || first == "\t" {
                    versionSlice = versionSlice.dropFirst()
                }
                while let last = versionSlice.last, last == " " || last == "\t" {
                    versionSlice = versionSlice.dropLast()
                }
                return Version.Tools(Swift.String(versionSlice))
            }
            lineCount += 1
            if lineCount >= 30 { break }
        }
        return nil
    }

    /// Detect whether `source`'s leading 30 lines contain a Shape-γ
    /// magic-comment line whose version parses as
    /// ``Version/Tools``.
    fileprivate static func hasMagicComment(in source: Swift.String) -> Swift.Bool {
        Self.parseMagicCommentToolsVersion(in: source) != nil
    }

    /// Read a file's full contents into a `Swift.String`.
    ///
    /// `internal` (not `fileprivate`) so the sibling-file ``Channel`` and the
    /// detection helpers can share one file-read implementation. Nested
    /// accessor name per `[API-NAME-002]` — `Lint.File.Single.contents(of:)`.
    ///
    /// F-A2.3 cascade: typed `File.Path` parameter.
    internal static func contents(of path: File.Path) throws(File.System.Read.Full.Error) -> Swift.String {
        let bytes: [Byte] = try File(path).read.full { (span: Swift.Span<Byte>) -> [Byte] in
            var array: [Byte] = []
            array.reserveCapacity(span.count)
            for i in 0..<span.count {
                array.append(span[i])
            }
            return array
        }
        return Swift.String(decoding: bytes, as: UTF8.self)
    }

    /// Full dispatch path for a Shape-γ consumer:
    /// extract deps → resolve parent chain → materialize eval project
    /// → spawn `swift run`.
    ///
    /// Parent-chain resolution: the consumer's `Lint.swift` MAY carry
    /// one or more `// parent: <URL>` directives. Each parent is
    /// fetched via `Manifest.Resolver.walkParents`, evaluated via the
    /// subprocess manifest loader as a wire-format
    /// ``Lint/Manifest``, and folded parent-first into a single
    /// effective Manifest. The folded Manifest is JSON-serialized to
    /// a temp file; the file path is passed to the dispatched
    /// executable via the `SWIFT_LINTER_PARENT_MANIFEST` environment
    /// variable. The executable's
    /// ``Lint/run(dependencies:rules:)`` reads the env var, lifts
    /// the parent Manifest against the local rule registry, and
    /// threads the result as `inheriting:`.
    ///
    /// Returns the spawned `swift run` invocation's exit code as an
    /// `Int32`. A terminating signal `s` is encoded as `-s` so
    /// callers can distinguish abnormal termination from a regular
    /// non-zero exit.
    ///
    /// `arguments` is forwarded to the dispatched `Lint` executable
    /// (the consumer's `Lint.swift` as compiled in the eval project).
    ///
    /// `output` is the CLI's requested output shape. When it is
    /// ``Output/nonStandard`` (`--format` other than text, or a non-advisory
    /// `--exit-policy`) the prebuilt-runner fast path is bypassed via
    /// ``route(output:classification:)`` — the runner bakes text + advisory
    /// and cannot reshape its output. Defaults to ``Output/standard``.
    ///
    /// `nonce` is a per-run-unique token (the CLI supplies a random one) woven
    /// into the selection / parent ``Channel`` temp-file names so concurrent
    /// `swift-linter` runs on the same consumer root no longer clobber a FIXED
    /// path. Defaults to `""` (the stable name) for single-process library and
    /// test callers.
    ///
    /// F-A2.3 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
    /// `consumerPackageRoot` is typed `File.Path`. The CLI binding
    /// converts the CLI-supplied bare string once at the boundary
    /// per `[IMPL-010]`.
    public static func dispatch(
        at consumerPackageRoot: File.Path,
        arguments: [Swift.String],
        output: Output = .standard,
        nonce: Swift.String = ""
    ) throws(Lint.File.Single.Error) -> Swift.Int32 {
        let consumerLintSwiftPath: File.Path = consumerPackageRoot / "Lint.swift"

        // 1. Read source.
        let source: Swift.String
        do throws(File.System.Read.Full.Error) {
            source = try Self.contents(of: consumerLintSwiftPath)
        } catch {
            throw .readFailed(path: consumerLintSwiftPath, description: "\(error)")
        }

        // 2. Validate magic-comment.
        guard Self.hasMagicComment(in: source) else {
            throw .missingToolsVersion(path: consumerLintSwiftPath)
        }

        // 3. Parse `Lint.swift` exactly ONCE. The single parsed tree is threaded
        // to BOTH the fast-path classifier (next) and — only on the eval branch
        // — the dependency extractor, so dispatch never parses the same source
        // twice.
        let parsed: SourceFileSyntax = Parser.parse(source: source)

        // 3.5. Phase-3 fast path
        // (Research/near-instant-lint-with-external-rule-loading.md): when a
        // prebuilt "standard runner" is provisioned — its binary named by the
        // `SWIFT_LINTER_RUNNER` environment variable — AND the consumer's
        // active rule set is exactly the standard `Lint.Rule.Bundle.primitives`
        // that runner bakes, lint via the runner. This skips the per-run eval
        // materialize-compile (the ~155s SwiftSyntax-from-source floor that
        // dominates a cold eval) and lints warm in ~0.65s.
        //
        // Failure-safe and additive: an unset `SWIFT_LINTER_RUNNER` (the local
        // and pre-rollout default) OR any non-`fastPathStandardBundle`
        // classification (inline/custom rules, non-`primitives` bundle,
        // per-consumer excludes/enables, a `// parent:` chain) falls through to
        // the eval pipeline below. External, consumer-declared rule loading is
        // preserved on BOTH paths: the runner bundles the published standard
        // rule packs, and the eval fallback compiles the consumer's declared
        // packs (including inline rules) exactly as before.
        //
        // `output` gates the fast path too: a non-`.standard` request
        // (`--format sarif`, non-advisory `--exit-policy`) routes to eval via
        // ``route(output:classification:)`` — the runner bakes text + advisory
        // and cannot reshape its output, so it must never be entered for a
        // shape it cannot produce.
        //
        // Classify-before-extract: the fast path needs NO dependency extraction
        // (the runner bakes its own packs), so classification runs FIRST. A
        // malformed `.package(...)` declaration therefore no longer blocks a
        // fast-path consumer — dependency extraction is deferred to the eval
        // branch, which is the only path that actually consumes the deps.
        if let runnerBinary: Swift.String = Environment.read("SWIFT_LINTER_RUNNER") {
            switch Self.route(
                output: output,
                classification: Lint.File.Single.Classifier.classify(source: source, parsed: parsed)
            ) {
            case .fastPathStandardBundle:
                return try Self.runStandardRunner(
                    binary: runnerBinary,
                    consumerPackageRoot: consumerPackageRoot,
                    arguments: arguments,
                    selection: nil,
                    nonce: nonce
                )
            case .fastPathStandardBundleExcluding(let disabled):
                // The consumer activates Bundle.primitives minus `disabled`.
                // Pass that selection to the runner as a Lint.Manifest; the
                // runner overlays it on its baked registry so it lints exactly
                // the consumer's reduced rule set (Bundle.primitives MINUS the
                // exclusions) — no per-run recompile.
                return try Self.runStandardRunner(
                    binary: runnerBinary,
                    consumerPackageRoot: consumerPackageRoot,
                    arguments: arguments,
                    selection: Lint.Manifest(disabled: disabled),
                    nonce: nonce
                )
            case .evalFallback:
                break  // fall through to the eval pipeline
            }
        }

        // 3.6. EVAL branch. Extract `Lint.run(dependencies:)` clauses from the
        // already-parsed tree — only the eval path materializes a project and
        // therefore needs the consumer's declared `.package(...)` dependencies.
        let extractedDependencies: [Package.Dependency] = try Lint.File.Single.Extractor.dependencies(
            parsed: parsed,
            sourcePath: consumerLintSwiftPath,
            consumerPackageRoot: consumerPackageRoot
        )

        // 4. Resolve parent chain (Lint-specific; writes the folded
        // `Lint.Manifest` to a temp JSON file and returns its path).
        // The helper self-creates `.swift-lint/` so it runs cleanly
        // before Manifest.Executable.dispatch materializes
        // `.swift-lint/eval/` over the same parent directory.
        let parentManifestPath: File.Path? = try Self.resolveParentChain(
            consumerSource: source,
            consumerPackageRoot: consumerPackageRoot,
            nonce: nonce
        )

        // 5–6. Resolve the engine dependency the generated Package.swift
        // references, then prepend it to the consumer's extracted deps.
        // Precedence (Phase 0,
        // Research/near-instant-lint-with-external-rule-loading.md):
        //   (a) SWIFT_LINTER_PATH set → local-dev `.path(...)` dependency on
        //       the engine source tree (HEAD). Preserves the inner-loop
        //       workflow and lets a source checkout dispatch the eval.
        //   (b) otherwise → branch-pinned `.url(..., branch:)` dependency on
        //       the engine `Linter` library (tag-free; tracks `main` per the
        //       ecosystem convention), so a standalone CLI binary (which has
        //       no engine source tree) can dispatch the eval.
        let linterDependency: Package.Dependency
        if let rawPath: Swift.String = Environment.read("SWIFT_LINTER_PATH") {
            let linterPathTyped: Paths.Path
            do throws(Paths.Path.Error) {
                linterPathTyped = try Paths.Path(rawPath)
            } catch {
                throw .materializationFailed(
                    reason: "SWIFT_LINTER_PATH `\(rawPath)` is not a valid path: \(error)"
                )
            }
            linterDependency = Package.Dependency(
                source: .path(linterPathTyped),
                name: "swift-linter",
                products: ["Linter"]
            )
        } else {
            linterDependency = try Self.publishedEngineDependency()
        }
        let dependencies: [Package.Dependency] = [linterDependency] + extractedDependencies

        // 7. Build environment (parent-chain channel variable when present).
        let environment: [Swift.String: Swift.String]?
        if let path: File.Path = parentManifestPath {
            var snapshot: Environment.Snapshot = Environment.Snapshot.current()
            snapshot.values[Channel.parent.variable] = path.string
            environment = snapshot.values
        } else {
            environment = nil
        }

        // 8. Build Manifest.Executable.Configuration.
        let evalRoot: File.Path = consumerPackageRoot / ".swift-lint" / "eval"
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

        // 9. Hand off to Manifest.Executable.dispatch; map errors at
        // the boundary so Lint.File.Single.Error stays the consumer-
        // facing throw shape.
        do throws(Manifest.Executable.Error) {
            return try Manifest.Executable.dispatch(configuration: configuration)
        } catch {
            switch error {
            case .readFailed(let path, let description):
                throw .readFailed(path: path, description: description)
            case .materializationFailed(let reason):
                throw .materializationFailed(reason: reason)
            case .spawnFailed(let consumerPackageRoot, let description):
                throw .spawnFailed(consumerPackageRoot: consumerPackageRoot, description: description)
            }
        }
    }

    /// Spawn the prebuilt "standard runner" to lint the consumer's
    /// declared targets, returning its exit code.
    ///
    /// Mirrors ``Manifest/Executable/dispatch(configuration:)``'s spawn
    /// shape — `/usr/bin/env <runner> <arguments>` via
    /// ``Process/Spawn`` with the parent's stdio inherited — so the
    /// runner's diagnostic stdout streams straight through to the
    /// caller. `environment: nil` inherits the parent environment
    /// (PATH, the toolchain runtime paths) per
    /// ``Process/Spawn`` semantics.
    ///
    /// `arguments` is the consumer's forwarded CLI argument vector (the
    /// lint-target paths). It is forwarded VERBATIM so the fast path
    /// lints exactly the paths the eval path lints:
    /// ``Manifest/Executable/dispatch(configuration:)`` appends the same
    /// `arguments` to its `swift run … Lint` invocation, and both the
    /// runner and the eval-compiled `Lint` resolve them against the
    /// inherited cwd. (The prior `[binary, consumerRoot]` invocation
    /// dropped multi-path / non-cwd targets — a silent fast-path/eval
    /// divergence; see ``runnerInvocation(binary:arguments:)``.)
    ///
    /// A terminating signal `s` is encoded as `-s`, matching
    /// ``dispatch(at:arguments:)``'s eval-path convention, so callers
    /// distinguish abnormal termination from a non-zero exit.
    ///
    /// When `selection` is non-`nil` (a pure-bundle consumer with
    /// `.excluding(rules:)`), it is written via ``Channel/selection`` (a
    /// per-run-unique file under `<consumerRoot>/.swift-lint/`) and the path is
    /// passed to the runner in the channel's environment variable; the runner's
    /// `Lint.run(bundle:)` reads it via ``Channel/read()`` and overlays it on
    /// its baked registry so it lints `Bundle.primitives` minus the consumer's
    /// exclusions. `nil` runs the full baked bundle (bare-bundle consumer).
    fileprivate static func runStandardRunner(
        binary: Swift.String,
        consumerPackageRoot: File.Path,
        arguments: [Swift.String],
        selection: Lint.Manifest?,
        nonce: Swift.String
    ) throws(Lint.File.Single.Error) -> Swift.Int32 {
        let environment: [Swift.String: Swift.String]?
        if let selection: Lint.Manifest = selection {
            let manifestPath: File.Path
            do throws(Channel.Error) {
                manifestPath = try Channel.selection.write(
                    selection,
                    consumerPackageRoot: consumerPackageRoot,
                    nonce: nonce
                )
            } catch {
                throw .materializationFailed(reason: "write selection manifest: \(error)")
            }
            var snapshot: Environment.Snapshot = Environment.Snapshot.current()
            snapshot.values[Channel.selection.variable] = manifestPath.string
            environment = snapshot.values
        } else {
            environment = nil  // inherit the parent environment
        }
        let invocation: [Swift.String] = Self.runnerInvocation(binary: binary, arguments: arguments)
        let spawnConfiguration = Process.Spawn.Configuration(
            executable: "/usr/bin/env",
            arguments: invocation,
            environment: environment
        )
        let status: Process.Status
        do throws(Process.Error) {
            status = try Process.Spawn.run(spawnConfiguration).status
        } catch {
            throw .spawnFailed(
                consumerPackageRoot: consumerPackageRoot,
                description: "standard-runner spawn failed: \(error)"
            )
        }
        switch status {
        case .exited(let code): return code
        case .signaled(let signal): return -signal
        case .stopped(let signal): return -signal
        }
    }

    /// Build the prebuilt-runner invocation argv: the runner `binary`
    /// followed by the consumer's forwarded CLI `arguments` (the lint-target
    /// paths).
    ///
    /// Forwarding `arguments` verbatim is what keeps the fast path and the
    /// eval path in lock-step:
    /// ``Manifest/Executable/dispatch(configuration:)`` builds
    /// `["swift", "run", …, "Lint"] + configuration.arguments`, where
    /// `configuration.arguments` is the same vector. So a multi-path
    /// invocation (`swift-linter Sources Tests`) lints `Sources` AND `Tests`
    /// on BOTH paths, and an empty `arguments` falls through to
    /// ``Lint/run(configuration:)``'s `["."]` default on both. The earlier
    /// `[binary, consumerPackageRoot.string]` form ignored `arguments`
    /// entirely — the fast path silently linted only the package root, a
    /// wrong-result-that-exits-0 divergence from the eval path.
    ///
    /// Pure + `internal` so the forwarding contract is unit-testable without a
    /// real ``Process/Spawn``.
    internal static func runnerInvocation(
        binary: Swift.String,
        arguments: [Swift.String]
    ) -> [Swift.String] {
        [binary] + arguments
    }

    /// The runner-vs-eval routing verdict, combining the requested `output`
    /// shape with the source `classification`.
    ///
    /// `.standard` output defers entirely to the classifier (the source
    /// decides). Any ``Output/nonStandard`` request forces
    /// ``Lint/File/Single/Classification/evalFallback(reason:)`` REGARDLESS of
    /// the source — the prebuilt runner bakes text + advisory output and
    /// cannot reproduce a SARIF format or a strict exit policy, so it must
    /// never be taken for such a request. Pure + `internal` so the gate is
    /// unit-testable without a real ``Process/Spawn``.
    internal static func route(
        output: Output,
        classification: Lint.File.Single.Classification
    ) -> Lint.File.Single.Classification {
        switch output {
        case .standard:
            return classification
        case .nonStandard:
            return .evalFallback(
                reason: "consumer requested an output shape the standard runner cannot produce "
                    + "(non-text `--format` or non-advisory `--exit-policy`)"
            )
        }
    }

    /// Walk the parent chain expressed in `consumerSource` and write
    /// the folded `Lint.Manifest` to a temp JSON file. Returns the
    /// path to the file when a chain is present, `nil` when no
    /// parent directive is found.
    ///
    /// Parent eval uses the same dependency set as
    /// ``Lint/Driver/configuration(at:manifestOverride:onMissingLinterPath:)``
    /// — JSON, File_System, Linter — resolved against
    /// `SWIFT_LINTER_PATH`. When the env var is unset the resolver
    /// cannot evaluate parents; the method returns `nil` and lint
    /// proceeds without parent inheritance.
    fileprivate static func resolveParentChain(
        consumerSource: Swift.String,
        consumerPackageRoot: File.Path,
        nonce: Swift.String
    ) throws(Lint.File.Single.Error) -> File.Path? {
        guard let linterPath: Swift.String = Environment.read("SWIFT_LINTER_PATH") else {
            return nil
        }
        // F-A1.11 (audit `2026-05-12-typed-primitive-adoption-audit.md`):
        // `Paths.Path.parent` replaces the prior `linterPath + "/.."`
        // dot-segment suffix; the typed primitive owns dot-segment
        // semantics. The workspace is the parent directory of the
        // swift-linter package — the env var points at the package
        // root by contract. Parse / parent failure folds into the
        // method's documented silent-fallback contract (return `nil`
        // → no parent inheritance).
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
            )
        ]
        let parentChain: [Lint.Manifest]
        do throws(Manifest.Resolver<Lint.Manifest, Lint.Manifest>.Error) {
            parentChain = try Manifest.Resolver<Lint.Manifest, Lint.Manifest>.walkParents(
                from: consumerSource,
                filename: "Lint.swift",
                dependencies: parentDependencies
            )
        } catch {
            // Parent chain failure — silent fall-through to no
            // inheritance. The dispatch can still proceed; the
            // consumer's own activations are unaffected.
            return nil
        }
        guard !parentChain.isEmpty else {
            return nil
        }
        let folded: Lint.Manifest = Self.foldParents(parentChain)
        // Write via the parent ``Channel`` (self-creates `.swift-lint/`, atomic
        // write, per-run-unique name). The dispatch resolves the parent chain
        // BEFORE handing off to Manifest.Executable.dispatch, so the channel
        // write runs cleanly before the eval project materializes over the same
        // `.swift-lint/` parent directory.
        do throws(Channel.Error) {
            return try Channel.parent.write(folded, consumerPackageRoot: consumerPackageRoot, nonce: nonce)
        } catch {
            throw .materializationFailed(reason: "write parent manifest: \(error)")
        }
    }

    /// Fold a parent-first chain of `Lint.Manifest` values into a
    /// single effective Manifest. Order is preserved (root-most first,
    /// closest-to-consumer last); the consumer's
    /// ``Lint/Configuration/Rules/effective`` handles dedup and
    /// override semantics (later wins per rule ID).
    fileprivate static func foldParents(_ chain: [Lint.Manifest]) -> Lint.Manifest {
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

    /// Dispatched-executable side of the parent-chain mechanism: read the parent
    /// `Lint.Manifest` via the parent ``Channel`` and lift it against the
    /// supplied local rule `registry`.
    ///
    /// Returns the resulting `Lint.Configuration` when the parent channel's
    /// variable is SET and the file reads + parses; returns `nil` ONLY when the
    /// variable is UNSET (no parent chain was resolved by the coordinator, or
    /// the executable is run directly without coordinator setup).
    ///
    /// Fail-loud: a SET-but-unreadable/unparseable parent manifest THROWS
    /// ``Channel/Error`` rather than silently dropping the parent's rules. This
    /// is the parent-channel half of the unified ``Channel`` guarantee — the
    /// caller (`Lint.run(dependencies:rules:)`) surfaces the failure and exits
    /// non-zero instead of linting with a silently-narrowed rule set.
    public static func configuration(
        parentOf registry: [Lint.Rule.ID: Lint.Rule]
    ) throws(Channel.Error) -> Lint.Configuration? {
        guard let manifest: Lint.Manifest = try Channel.parent.read() else {
            return nil
        }
        return Lint.Configuration.lift(manifest: manifest, registry: registry)
    }
}
