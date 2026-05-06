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
import Linter
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
        be expressed as a regex on source text. Phase 1 ships R5 \
        (`__unchecked:` argument label at call sites only).

        Reads a `Lint.swift` typed-DSL config at the consumer package root \
        (mirroring `Package.swift`); when absent, the CLI activates all \
        built-in rules at default severity.
        """
    )

    @Argument(help: "Paths to lint (files or directories). Defaults to current directory.")
    var paths: [String] = ["."]

    @Option(name: .long, help: "Output format. Choices: text (default; SwiftLint-compatible textual lines), sarif (SARIF 2.1.0 JSON for CI artifact upload).")
    var format: Lint.Reporter.Format = .text

    @Option(name: .long, help: "Path to Lint.swift. Defaults to <path>/Lint.swift if present.")
    var lintSwiftPath: String?

    @Option(name: [.long, .customLong("strict")], help: "Exit policy. Choices: advisory (exit 0 always), strict (exit non-zero when any finding has severity:error). The legacy --strict flag is honored.")
    var exitPolicy: Lint.Run.ExitPolicy = .advisory

    func run() throws {
        let configuration = resolveConfiguration()
        let findings = try Lint.Run.run(paths: paths, configuration: configuration)
        emit(findings)
        if exitPolicy == .strict && findings.contains(where: { $0.severity == .error }) {
            throw ExitCode.failure
        }
    }

    /// Resolves the configuration to use for this run.
    ///
    /// Phase 1.5 Item 5 v1: detection-only via `Lint.SwiftDriver`.
    /// Lint.swift presence is acknowledged; full subprocess evaluation
    /// is OQ-EV1 (Phase 2 v2). The v1-default Configuration activates
    /// every `Lint.Rule.builtIn` rule at default severity, matching the
    /// empirical canonical-tier2-derived shape.
    func resolveConfiguration() -> Lint.Configuration {
        let consumerRoot = paths.first ?? "."
        return Lint.SwiftDriver.resolveConfiguration(consumerPackageRoot: consumerRoot)
    }

    func emit(_ findings: [Lint.Finding]) {
        // The Reporter is parameterized over a typed write surface
        // (Terminal.Stream.Write) plus a consumer-supplied emit closure.
        // Until swift-terminal-primitives gains an L2 syscall extension
        // for write, the CLI bridges via Swift.print at the I/O boundary
        // (OQ-T2 in the Phase 1.5 HANDOFF). The typed surface still drives
        // the API; the closure is the temporary syscall stand-in.
        let writer: (Terminal.Stream.Write, String) -> Void = { _, line in
            print(line)
        }
        switch format {
        case .text:
            Lint.Reporter.emit(findings: findings, to: Terminal.Stream.stdout.write, via: writer)
        case .sarif:
            Lint.Reporter.SARIF.emit(findings: findings, to: Terminal.Stream.stdout.write, via: writer)
        }
    }
}
