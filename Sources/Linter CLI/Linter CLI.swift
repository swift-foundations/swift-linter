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

@main
struct SwiftLinter: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-linter",
        abstract: "SwiftSyntax-based AST linter for the swift-primitives ecosystem.",
        discussion: """
        Augments SwiftLint by hosting AST-shaped rules whose predicate cannot \
        be expressed as a regex on source text. Phase 1 ships R5 \
        (`__unchecked:` argument label at call sites only).

        Reads `.swift-primitives-lint.yml` from the package root if present; \
        otherwise activates all built-in rules at default severity.
        """
    )

    @Argument(help: "Paths to lint (files or directories). Defaults to current directory.")
    var paths: [String] = ["."]

    @Flag(name: .long, help: "Emit SARIF JSON instead of plain text.")
    var sarif: Bool = false

    @Option(name: .long, help: "Path to .swift-primitives-lint.yml. Defaults to <path>/.swift-primitives-lint.yml.")
    var configPath: String?

    @Flag(name: .long, help: "Exit with a non-zero status if any finding is severity:error.")
    var strict: Bool = false

    func run() throws {
        let rules = Lint.Rule.builtIn
        let knownRuleIDs: Set<String> = Set(rules.map { type(of: $0).id })
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

    func loadConfiguration(knownRuleIDs: Set<String>) throws -> Lint.Configuration {
        if let configPath {
            return try Lint.Configuration.Loader.load(from: configPath, knownRuleIDs: knownRuleIDs)
        }
        for path in paths {
            let candidate = "\(path)/.swift-primitives-lint.yml"
            if let configuration = try? Lint.Configuration.Loader.load(from: candidate, knownRuleIDs: knownRuleIDs) {
                return configuration
            }
        }
        return Lint.Configuration(activatedRuleIDs: knownRuleIDs)
    }

    func emit(_ findings: [Lint.Finding]) {
        if sarif {
            print(Lint.Reporter.SARIF.report(for: findings))
            return
        }
        let text = Lint.Reporter.text(for: findings)
        if !text.isEmpty {
            print(text)
        }
    }
}
