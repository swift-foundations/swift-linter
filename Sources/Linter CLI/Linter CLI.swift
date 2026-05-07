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
import Linter
import Linter_Reporter_Text
import Linter_Reporter_SARIF
import Terminal_Primitives

extension Lint.Reporter.Format: ExpressibleByArgument {}
extension Lint.Run.ExitPolicy: ExpressibleByArgument {}

@main
struct SwiftLinter: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-linter",
        abstract: "SwiftSyntax-based AST linter for the swift-primitives ecosystem.",
        discussion: """
        Augments SwiftLint by hosting AST-shaped rules whose predicate cannot \
        be expressed as a regex on source text. The engine ships rule-pack-\
        agnostic — without an explicit configuration, zero rules fire.

        Two consumer shapes are detected at the package root: a `Lint/` \
        nested SwiftPM package (recommended; consumers wire engine + rule \
        packs in its `Package.swift`), or a single-file `Lint.swift` (sugar \
        form, currently inert). When neither is present, the CLI runs with \
        the empty default Configuration.
        """
    )

    @Argument(help: "Paths to lint (files or directories). Defaults to current directory.")
    var paths: [Swift.String] = ["."]

    @Option(name: .long, help: "Output format. Choices: text (default; SwiftLint-compatible textual lines), sarif (SARIF 2.1.0 JSON for CI artifact upload).")
    var format: Lint.Reporter.Format = .text

    @Option(name: .long, help: "Path to Lint.swift. Defaults to <path>/Lint.swift if present.")
    var lintSwiftPath: Swift.String?

    @Option(name: [.long, .customLong("strict")], help: "Exit policy. Choices: advisory (exit 0 always), strict (exit non-zero when any finding has severity:error). The legacy --strict flag is honored.")
    var exitPolicy: Lint.Run.ExitPolicy = .advisory

    func run() throws {
        let consumerRoot = paths.first ?? "."

        // Lint/ nested-package dispatch (architecture cohort Phase A).
        // When the consumer opts into the nested-package shape via a
        // `Lint/Package.swift`, swift-linter delegates the run to the
        // consumer's Lint/ executable (which links engine + rule packs
        // declared in its Lint/Package.swift). The dispatched
        // executable's stdout IS the authoritative diagnostic stream;
        // this CLI becomes a coordinator under that path.
        if let dispatchedExitCode = Lint.Driver.dispatchNestedIfPresent(
            consumerPackageRoot: consumerRoot,
            arguments: paths
        ) {
            if dispatchedExitCode != 0 {
                throw ExitCode(dispatchedExitCode)
            }
            return
        }

        // Single-file `Lint.swift` fallback (existing chain-resolution
        // flow, unchanged).
        let configuration = resolveConfiguration()
        // ArgumentParser hands `[String]`; validate at the CLI boundary
        // exactly once via `try File.Path(_:)` so the engine receives
        // typed paths from here down [IMPL-010].
        let typedPaths: [File.Path] = try paths.map { try File.Path($0) }
        let findings = try Lint.Run.run(paths: typedPaths, configuration: configuration)
        emit(findings)
        if exitPolicy == .strict && findings.contains(where: { $0.severity == .error }) {
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
    func resolveConfiguration() -> Lint.Configuration {
        let consumerRoot = paths.first ?? "."
        return Lint.Driver.resolveConfiguration(
            consumerPackageRoot: consumerRoot,
            lintSwiftPathOverride: lintSwiftPath
        )
    }

    func emit(_ findings: [Lint.Finding]) {
        // Phase 2 Stream C: emit directly via Terminal.Stream.Write's
        // L2 syscall extension (POSIX: swift-iso-9945; Windows:
        // swift-windows-32). OQ-T2 from Phase 1.5 is closed.
        switch format {
        case .text:
            Lint.Reporter.emit(findings: findings, to: Terminal.Stream.stdout.write)
        case .sarif:
            Lint.Reporter.SARIF.emit(findings: findings, to: Terminal.Stream.stdout.write)
        }
    }
}
