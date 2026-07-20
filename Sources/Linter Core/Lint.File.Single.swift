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
internal import SwiftParser
internal import SwiftSyntax

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
    /// Namespace for the single-file (`Lint.swift`) consumer manifest shape.
    public enum Single: Swift.Sendable {}
}

extension Lint.File.Single {
    /// Canonicalize a CLI-supplied consumer-root path to its absolute
    /// form.
    ///
    /// When the path is `"."` or empty (the canonical
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

    /// Read a file's full contents into a `Swift.String`.
    ///
    /// `internal` (not `fileprivate`) so the sibling-file ``Channel`` and the
    /// detection helpers can share one file-read implementation. Nested
    /// accessor name per `[API-NAME-002]` — `Lint.File.Single.contents(of:)`.
    ///
    /// F-A2.3 cascade: typed `File.Path` parameter.
    internal static func contents(of path: File.Path) throws(File.System.Read.Full.Error) -> Swift.String {
        // `read.full` yields a borrowed `Span<Byte>`; copying it out requires an
        // index walk (`Span` is `~Escapable` and not a `Sequence`, so neither
        // `Array(span)` nor `for byte in span` is available). This is the
        // canonical low-level Span→Array copy, not a reinvention.
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
    /// ``Output/nonStandard`` (`--format` other than text) the prebuilt-runner
    /// fast path is bypassed via ``route(output:classification:)`` — the
    /// runner bakes text output and cannot reshape it. The exit policy rides
    /// the ``Lint/Run/Policy/Channel`` environment variable instead and gates
    /// nothing here. Defaults to ``Output/standard``.
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
    ) throws(Self.Error) -> Swift.Int32 {
        let consumerLintSwiftPath: File.Path = consumerPackageRoot / "Lint.swift"

        // 1. Read source.
        let source: Swift.String
        do throws(File.System.Read.Full.Error) {
            source = try Self.contents(of: consumerLintSwiftPath)
        } catch {
            throw .readFailed(path: consumerLintSwiftPath, description: "\(error)")
        }

        // 2. Validate magic-comment.
        guard Detection.hasMagicComment(in: source) else {
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
        // (`--format sarif`) routes to eval via
        // ``route(output:classification:)`` — the runner bakes text output
        // and cannot reshape it, so it must never be entered for a shape it
        // cannot produce. The exit policy does NOT gate routing: both
        // dispatch targets honor the CLI-exported exit-policy channel at the
        // shared `Lint.run(configuration:)` terminal.
        //
        // Classify-before-extract: the fast path needs NO dependency extraction
        // (the runner bakes its own packs), so classification runs FIRST. A
        // malformed `.package(...)` declaration therefore no longer blocks a
        // fast-path consumer — dependency extraction is deferred to the eval
        // branch, which is the only path that actually consumes the deps.
        if let runnerBinary: Swift.String = Environment.read("SWIFT_LINTER_RUNNER") {
            switch Self.route(
                output: output,
                classification: Self.Classifier.classify(source: source, parsed: parsed)
            ) {
            case .fastPathStandardBundle:
                return try Runner.run(
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
                return try Runner.run(
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

        // 3.6. EVAL fallback. Materialize + compile + spawn the consumer's
        // `Lint.swift` (engine + declared rule packs), preserving fully-dynamic
        // consumer-declared rule loading. ``Eval/run`` owns the
        // extract-deps → parent-chain → engine-dep → materialize → spawn
        // pipeline; dispatch stays thin (detect → classify → {runner | eval}).
        return try Eval.run(
            consumerPackageRoot: consumerPackageRoot,
            consumerLintSwiftPath: consumerLintSwiftPath,
            source: source,
            parsed: parsed,
            arguments: arguments,
            nonce: nonce
        )
    }

    /// The runner-vs-eval routing verdict, combining the requested `output`
    /// shape with the source `classification`.
    ///
    /// `.standard` output defers entirely to the classifier (the source
    /// decides). Any ``Output/nonStandard`` request forces
    /// ``Lint/File/Single/Classification/evalFallback(reason:)`` REGARDLESS of
    /// the source — the prebuilt runner bakes text output and cannot
    /// reproduce a SARIF format, so it must never be taken for such a
    /// request. (Exit policy is channel-borne and does not gate routing.)
    /// Pure + `internal` so the gate is unit-testable without a real
    /// ``Process/Spawn``.
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
                    + "(non-text `--format`)"
            )
        }
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
