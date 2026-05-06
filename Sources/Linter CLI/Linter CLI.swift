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

import ArgumentParser
import Linter
import Terminal_Primitives

@main
struct SwiftLinter: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-linter",
        abstract: "SwiftSyntax-based AST linter for the swift-primitives ecosystem.",
        discussion: """
        Augments SwiftLint by hosting AST-shaped rules whose predicate cannot \
        be expressed as a regex on source text. Phase 1 ships R5 \
        (`__unchecked:` argument label at call sites only).

        Reads `.swift-linter.yml` from the package root if present; \
        otherwise activates all built-in rules at default severity.
        """
    )

    @Argument(help: "Paths to lint (files or directories). Defaults to current directory.")
    var paths: [String] = ["."]

    @Flag(name: .long, help: "Emit SARIF JSON instead of plain text.")
    var sarif: Bool = false

    @Option(name: .long, help: "Path to .swift-linter.yml. Defaults to <path>/.swift-linter.yml.")
    var configPath: String?

    @Flag(name: .long, help: "Exit with a non-zero status if any finding is severity:error.")
    var strict: Bool = false

    func run() throws {
        let rules = Lint.Rule.builtIn
        let knownRuleIDs: Set<Lint.Rule.ID> = Set(rules.map { type(of: $0).id })
        let configuration = try loadConfiguration(knownRuleIDs: knownRuleIDs)
        let findings = try Lint.Run.run(
            paths: paths,
            configuration: configuration,
            rules: rules
        )
        emit(findings)
        if strict && findings.contains(where: { $0.severity == .error }) {
            throw ExitCode.failure
        }
    }

    func loadConfiguration(knownRuleIDs: Set<Lint.Rule.ID>) throws -> Lint.Configuration {
        if let configPath {
            return try Lint.Configuration.Loader.load(from: configPath, knownRuleIDs: knownRuleIDs)
        }
        for path in paths {
            let candidate = "\(path)/.swift-linter.yml"
            if let configuration = try? Lint.Configuration.Loader.load(from: candidate, knownRuleIDs: knownRuleIDs) {
                return configuration
            }
        }
        return Lint.Configuration(activatedRuleIDs: knownRuleIDs)
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
        if sarif {
            Lint.Reporter.SARIF.emit(findings: findings, to: Terminal.Stream.stdout.write, via: writer)
            return
        }
        Lint.Reporter.emit(findings: findings, to: Terminal.Stream.stdout.write, via: writer)
    }
}
