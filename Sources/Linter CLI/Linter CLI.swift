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

public import ArgumentParser
import File_System
public import File_System_Core
import Kernel
import Linter
import Linter_Reporter_SARIF
import Linter_Reporter_Text
import Terminal_Primitives

extension Lint.Reporter.Format: ExpressibleByArgument {}
extension Lint.Run.Policy: ExpressibleByArgument {}

extension File.Path: @retroactive ExpressibleByArgument {
    /// Creates a path by validating the CLI-supplied argument string, or `nil` if invalid.
    public init?(argument: Swift.String) {
        do throws(Paths.Path.Error) {
            self = try File.Path(argument)
        } catch {
            return nil
        }
    }
}

extension Lint {
    @main
    struct CLI: ParsableCommand {
        @Argument(help: "Paths to lint (files or directories). Defaults to current directory.")
        var paths: [Swift.String] = ["."]

        @Option(name: .long, help: "Output format. Choices: text (default; SwiftLint-compatible textual lines), sarif (SARIF 2.1.0 JSON for CI artifact upload).")
        var format: Lint.Reporter.Format = .text

        @Option(name: .customLong("lint-swift-path"), help: "Path to Lint.swift. Defaults to <path>/Lint.swift if present.")
        var linter: File_System.File.Path?

        @Option(
            name: [.customLong("exit-policy"), .customLong("strict")],
            help: """
                Exit policy. Choices: advisory (exit 0 always), strict (exit non-zero when any \
                finding has severity:error). The legacy --strict flag is honored.
                """
        )
        var policy: Lint.Run.Policy = .advisory
    }
}

// `static let configuration`, `run()`, `resolveConfiguration`, and `emit` live
// in this extension per `[API-IMPL-008]` (minimal type body): the `@main`
// `ParsableCommand` struct body carries ONLY its `@Argument`/`@Option` stored
// properties (ArgumentParser binds the option vocabulary via those declared
// wrappers); the command's static configuration and behavior are extension
// members. `@main` + `ParsableCommand` conformance resolve through the extension
// (the `static var configuration` / `func run()` requirements are satisfied by
// extension members; the `@main` synthesized entry point finds them).
extension Lint.CLI {
    static let configuration = CommandConfiguration(
        commandName: "swift-linter",
        abstract: "SwiftSyntax-based AST linter for the swift-primitives ecosystem.",
        discussion: """
            Augments SwiftLint by hosting AST-shaped rules whose predicate cannot \
            be expressed as a regex on source text. The engine ships rule-pack-\
            agnostic — without an explicit configuration, zero rules fire.

            Three consumer shapes are detected at the package root, in priority \
            order: (1) a single-file `Lint.swift` with a `// swift-linter-tools-\
            version:` magic-comment header (Shape γ — recommended; declares \
            SwiftPM deps + rule activations in one file), (2) a `Lint/` nested \
            SwiftPM package (the prior recommended shape; consumers wire engine \
            + rule packs in its `Package.swift`), or (3) a legacy single-file \
            `Lint.swift` declaring `let manifest: Lint.Manifest` (inert post-\
            Phase-B.1 decouple). When none is present, the CLI runs with the \
            empty default Configuration.
            """
    )
}

extension Lint.CLI {
    // ArgumentParser's `ParsableCommand.run()` protocol requirement is
    // bare-throws; typed throws is unavailable here until upstream
    // adoption. The body throws three distinct types (`ExitCode`,
    // `Path.Error` via `try File.Path(_:)`, `Lint.Run.Error`) — they
    // unify to `any Error` at the boundary by necessity, not by choice.
    // swift-linter:disable:next untyped throws
    // REASON: signature forced by external protocol ArgumentParser.ParsableCommand.run()
    // (bare `throws`); typed throws is unavailable here until upstream adoption.
    // swiftlint:disable:next typed_throws_required
    func run() throws {
        // Resolve `"."` / empty to an absolute path before any
        // engine-side path arithmetic. SwiftPM rejects the literal
        // `"."` as a package name in the materialized eval project
        // (yields `unknown package '.'`); the CLI is the boundary
        // between user-supplied paths and engine internals, so cwd
        // resolution lives here per the platform skill's L3-unifier
        // composition discipline. Linter Core stays kernel-free.
        let consumerRootString: Swift.String = Lint.File.Single.canonicalize(
            consumerRoot: paths.first ?? ".",
            currentWorkingDirectory: {
                let result: Swift.String?
                do throws(ISO_9945.Kernel.Directory.Working.Error) {
                    result = try Kernel.Directory.Working.withCurrentBytes { (span: Swift.Span<UInt8>) -> Swift.String in
                        var bytes: [UInt8] = []
                        bytes.reserveCapacity(span.count)
                        for i in 0..<span.count {
                            bytes.append(span[i])
                        }
                        return Swift.String(decoding: bytes, as: UTF8.self)
                    }
                } catch {
                    // Silent-fallback: getcwd failure (e.g., removed)
                    // surfaces as the consumer-root-string unchanged.
                    result = nil
                }
                return result
            }
        )
        // F-A2.1 / F-A2.3 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
        // bare-string → `File.Path` conversion happens once at the
        // CLI boundary per `[IMPL-010]`. Every engine surface below
        // receives the typed value.
        let consumerRoot: File_System.File.Path = try File_System.File.Path(consumerRootString)

        // Single-file `Lint.swift` (Shape γ) dispatch — research
        // recommendation 2026-05-12-swift-linter-unified-consumer-manifest.md.
        // When the consumer places a `Lint.swift` at the package root
        // with a `// swift-linter-tools-version:` magic-comment header,
        // swift-linter parses it via SwiftSyntax to extract the
        // declared `.package(...)` dependencies, materializes an eval
        // project at `<consumerRoot>/.swift-lint/eval/`, and dispatches
        // `swift run --package-path <eval> Lint <args>`. The dispatched
        // executable IS the linter binary for the consumer.
        if Lint.File.Single.Detection.detect(at: consumerRoot) != nil {
            // The prebuilt-runner fast path can only reproduce the runner's
            // baked output shape (text format, advisory exit). Tell dispatch
            // whether the requested output is that shape; any other request
            // (`--format sarif`, `--exit-policy strict`) routes to the eval
            // fallback so the runner is never entered for output it cannot
            // produce.
            let output: Lint.File.Single.Output =
                (format == .text && policy == .advisory) ? .standard : .nonStandard
            // Per-run nonce (2f): woven into the selection / parent channel
            // temp-file names so concurrent `swift-linter` runs on the same
            // consumer root never clobber a FIXED path. A 64-bit random hex
            // token is unique-per-run with overwhelming probability; the CLI
            // is the right place to mint it (Linter Core stays kernel-free,
            // mirroring the injected cwd closure).
            let runNonce: Swift.String = Swift.String(
                UInt64.random(in: UInt64.min...UInt64.max),
                radix: 16
            )
            let dispatchedExitCode: Swift.Int32
            do throws(Lint.File.Single.Error) {
                dispatchedExitCode = try Lint.File.Single.dispatch(
                    at: consumerRoot,
                    arguments: paths,
                    output: output,
                    nonce: runNonce
                )
            } catch {
                do throws(ISO_9945.Kernel.IO.Write.Error) {
                    _ = try Terminal.Stream.stderr.write(
                        "[swift-linter] error: single-file dispatch failed: \(error)\n".utf8.lazy.map(Byte.init)
                    )
                } catch {
                    // Best-effort stderr write; broken pipe is acceptable.
                }
                throw ExitCode.failure
            }
            if dispatchedExitCode != 0 {
                throw ExitCode(dispatchedExitCode)
            }
            return
        }

        // Lint/ nested-package dispatch (architecture cohort Phase A).
        // When the consumer opts into the nested-package shape via a
        // `Lint/Package.swift`, swift-linter delegates the run to the
        // consumer's Lint/ executable (which links engine + rule packs
        // declared in its Lint/Package.swift). The dispatched
        // executable's stdout IS the authoritative diagnostic stream;
        // this CLI becomes a coordinator under that path.
        //
        // `onDispatchError` translates the typed `Manifest.NestedPackage.Error`
        // (silently suppressed at the library boundary) into a stderr
        // diagnostic. Without this hook the user sees a bare non-zero
        // exit with no explanation when the nested-package spawn fails.
        if let dispatchedExitCode = Lint.Driver.dispatch.nested(
            at: consumerRoot,
            arguments: paths,
            onDispatchError: { description in
                do throws(ISO_9945.Kernel.IO.Write.Error) {
                    _ = try Terminal.Stream.stderr.write(
                        "[swift-linter] error: nested-package dispatch failed: \(description)\n".utf8.lazy.map(Byte.init)
                    )
                } catch {
                    // Best-effort stderr write; broken pipe is acceptable.
                }
            }
        ) {
            if dispatchedExitCode != 0 {
                throw ExitCode(dispatchedExitCode)
            }
            return
        }

        let configuration: Lint.Configuration = resolveConfiguration(consumerRoot: consumerRoot)
        // ArgumentParser hands `[String]`; validate at the CLI boundary
        // exactly once via `try File.Path(_:)` so the engine receives
        // typed paths from here down [IMPL-010].
        // Typed-throws closure annotation (`throws(Paths.Path.Error)`): a
        // bare `paths.map { try … }` erases the typed throw through stdlib
        // `rethrows` to `any Error` and trips `result wrapper for rethrows
        // shim` ([IMPL-109]). The annotated closure keeps the throw typed and
        // rethrows it precisely, matching the `run(configuration:)` precedent.
        let typedPaths: [File_System.File.Path] = try paths.map { (raw: Swift.String) throws(Paths.Path.Error) in
            try File_System.File.Path(raw)
        }
        let findings: [Lint.Finding] = try Lint.Run.run(paths: typedPaths, configuration: configuration)
        emit(findings)
        if policy == .strict && findings.contains(where: { $0.record.severity == .error }) {
            throw ExitCode.failure
        }
    }

    /// Resolves the configuration to use for this run.
    ///
    /// Phase 2 v2: full Manifest.load subprocess evaluation. When the
    /// user passes `--lint-swift-path`, that explicit file path
    /// overrides the default detection at `<paths.first>/Lint.swift`.
    /// The driver falls back to a defaults-everything Configuration
    /// when no manifest is reachable (per supervisor block entry #5).
    ///
    /// `onMissingLinterPath` translates the silently-suppressed
    /// `SWIFT_LINTER_PATH`-unset case into a stderr diagnostic. The
    /// library still falls back to defaults-everything; the CLI tells
    /// the user why.
    ///
    /// F-A2.1 / F-A2.2: typed `File.Path` artery from CLI boundary
    /// down. The `--lint-swift-path` flag binds directly to a
    /// `File.Path?` via `ExpressibleByArgument`, so the override is
    /// already typed by the time it reaches here.
    fileprivate func resolveConfiguration(consumerRoot: File_System.File.Path) -> Lint.Configuration {
        return Lint.Driver.configuration(
            at: consumerRoot,
            manifestOverride: linter,
            onMissingLinterPath: {
                do throws(ISO_9945.Kernel.IO.Write.Error) {
                    _ = try Terminal.Stream.stderr.write(
                        "[swift-linter] error: SWIFT_LINTER_PATH environment variable not set; cannot resolve manifest dependencies. Falling back to default (zero-rules) configuration.\n".utf8.lazy
                            .map(Byte.init)
                    )
                } catch {
                    // Best-effort stderr write; broken pipe is acceptable.
                }
            }
        )
    }

    func emit(_ findings: [Lint.Finding]) {
        // Phase 2 Stream C: emit directly via Terminal.Stream.Write's
        // L2 syscall extension (POSIX: swift-iso-9945; Windows:
        // swift-windows-32). OQ-T2 from Phase 1.5 is closed.
        switch format {
        case .text:
            Lint.Reporter.Text.emit(findings: findings, to: Terminal.Stream.stdout.write)

        case .sarif:
            Lint.Reporter.SARIF.emit(findings: findings, to: Terminal.Stream.stdout.write)
        }
    }
}
