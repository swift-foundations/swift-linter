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

import Testing
import Foundation
import File_System
import SwiftSyntax
import SwiftParser
import Linter_Primitives
@testable import Linter_Core

extension Lint.Suppression {
    @Suite
    struct Test {
        @Suite struct Scanner {}
        @Suite struct EngineIntegration {}
    }
}

// MARK: - Scanner unit tests

extension Lint.Suppression.Test.Scanner {
    /// Parse `source` into a SwiftSyntax tree + converter pair and
    /// build the suppression map. Helper so each test reads as
    /// "given this source, the map has these entries".
    private static func scanSource(_ source: Swift.String, fileName: Swift.String = "<test>") -> Lint.Suppression {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: fileName, tree: tree)
        return Lint.Suppression.scan(tree: tree, converter: converter)
    }

    @Test
    func `Empty source yields empty suppression map`() {
        let map = Self.scanSource("")
        #expect(map.entries.isEmpty)
    }

    @Test
    func `Source with no directives yields empty suppression map`() {
        let source = """
        let x = 1
        let y = 2
        """
        let map = Self.scanSource(source)
        #expect(map.entries.isEmpty)
    }

    @Test
    func `disable next directive suppresses the immediately following code line`() {
        // Line 1: directive
        // Line 2: code (this is the suppressed line)
        let source = """
        // swift-linter:disable:next some rule
        let x = 1
        """
        let map = Self.scanSource(source)
        #expect(map.entries.count == 1)
        let entry = map.entries.first
        #expect(entry?.line == 2)
        #expect(entry?.ruleID.underlying == "some rule")
    }

    @Test
    func `disable next directive skips blank lines to next non-blank line`() {
        // Line 1: directive
        // Line 2: blank
        // Line 3: code (this is the suppressed line — the next CODE line)
        let source = """
        // swift-linter:disable:next some rule

        let x = 1
        """
        let map = Self.scanSource(source)
        #expect(map.entries.count == 1)
        #expect(map.entries.first?.line == 3)
    }

    @Test
    func `disable line directive suppresses the line carrying the directive`() {
        // Line 1: code, with the disable:line comment as trailing trivia
        // The directive applies to line 1 itself.
        let source = """
        let x = 1 // swift-linter:disable:line some rule
        let y = 2
        """
        let map = Self.scanSource(source)
        #expect(map.entries.count == 1)
        #expect(map.entries.first?.line == 1)
        #expect(map.entries.first?.ruleID.underlying == "some rule")
    }

    @Test
    func `disable next with REASON continuation captures reason prose`() {
        let source = """
        // swift-linter:disable:next some rule
        // REASON: this site is the typed-system bottom-out per [CONV-016].
        let x = 1
        """
        let map = Self.scanSource(source)
        #expect(map.entries.count == 1)
        #expect(map.entries.first?.line == 3)
        #expect(map.entries.first?.reason?.contains("typed-system bottom-out") == true)
    }

    @Test
    func `multiple disable directives produce independent entries`() {
        let source = """
        // swift-linter:disable:next rule one
        let a = 1
        // swift-linter:disable:next rule two
        let b = 2
        """
        let map = Self.scanSource(source)
        #expect(map.entries.count == 2)
        // First entry on line 2 (rule one); second entry on line 4 (rule two).
        #expect(map.entries.contains { $0.line == 2 && $0.ruleID.underlying == "rule one" })
        #expect(map.entries.contains { $0.line == 4 && $0.ruleID.underlying == "rule two" })
    }

    @Test
    func `suppresses returns true only for matching line and rule ID`() {
        let map = Lint.Suppression(entries: [
            Lint.Suppression.Entry(line: 5, ruleID: "rule one", reason: nil),
        ])
        #expect(map.suppresses(line: 5, ruleID: "rule one"))
        #expect(!map.suppresses(line: 5, ruleID: "rule two"))
        #expect(!map.suppresses(line: 6, ruleID: "rule one"))
    }
}

// MARK: - Engine integration

/// Synthetic fixture rule: fires on every line that contains the
/// identifier `targetCall`. Stand-in for any "real" rule — minimal
/// AST predicate so the test isolates suppression-map behavior.
extension Lint.Rule {
    fileprivate static let `suppression fixture` = Lint.Rule(
        id: "suppression fixture",
        defaultSeverity: .warning,
        findings: { source, severity in
            // The visitor emits one finding per `targetCall` token —
            // a stand-in for any rule that walks the tree.
            let visitor = LintSuppressionFixtureVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

internal final class LintSuppressionFixtureVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
        guard node.text == "targetCall" else { return .visitChildren }
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        matches.append(Diagnostic.Record(
            location: Source.Location(
                fileID: source.fileID,
                filePath: source.filePath,
                line: location.line,
                column: location.column
            ),
            severity: severity,
            identifier: "suppression fixture",
            message: "fixture rule fired"
        ))
        return .visitChildren
    }
}

extension Lint.Suppression.Test.EngineIntegration {
    /// Fixture root containing one Swift file `Sources/x.swift` that
    /// carries one `targetCall` identifier surrounded by suppression
    /// directives — the per-test source is composed dynamically via
    /// writing the fixture to a tmp directory.
    private static func writeFixture(content: Swift.String) throws -> File.Path {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lint-suppression-fixture-\(UUID().uuidString)")
        let sources = directory.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let file = sources.appendingPathComponent("x.swift")
        try content.data(using: .utf8)!.write(to: file)
        return try File.Path(directory.path)
    }

    @Test
    func `without directive, the fixture rule fires`() throws {
        // Two-line source, `targetCall` on line 1 — fires once.
        let root = try Self.writeFixture(content: """
        targetCall()
        let _ = 0
        """)
        let configuration = Lint.Configuration {
            .enable(.`suppression fixture`)
        }
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 1)
    }

    @Test
    func `disable next elides the next-line finding`() throws {
        // Directive on line 1, `targetCall` on line 2 — finding elided.
        let root = try Self.writeFixture(content: """
        // swift-linter:disable:next suppression fixture
        targetCall()
        """)
        let configuration = Lint.Configuration {
            .enable(.`suppression fixture`)
        }
        let outcome = try Lint.Run.runCapturingSuppressed(paths: [root], configuration: configuration)
        #expect(outcome.findings.isEmpty)
        #expect(outcome.suppressed.count == 1)
    }

    @Test
    func `disable line elides the same-line finding`() throws {
        // `targetCall` on line 1, with the disable directive as trailing trivia.
        let root = try Self.writeFixture(content: """
        targetCall() // swift-linter:disable:line suppression fixture
        """)
        let configuration = Lint.Configuration {
            .enable(.`suppression fixture`)
        }
        let outcome = try Lint.Run.runCapturingSuppressed(paths: [root], configuration: configuration)
        #expect(outcome.findings.isEmpty)
        #expect(outcome.suppressed.count == 1)
    }

    @Test
    func `disable next with mismatched rule ID does not elide finding`() throws {
        // Directive names a different rule — fixture rule still fires.
        let root = try Self.writeFixture(content: """
        // swift-linter:disable:next other rule
        targetCall()
        """)
        let configuration = Lint.Configuration {
            .enable(.`suppression fixture`)
        }
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 1)
    }

    @Test
    func `Configuration disabledRuleIDs elides all findings for that rule`() throws {
        // Two calls fire the fixture rule; configuration disables it
        // wholesale via disabledRuleIDs — both elided.
        let root = try Self.writeFixture(content: """
        targetCall()
        targetCall()
        """)
        let configuration = Lint.Configuration(
            disabledRuleIDs: ["suppression fixture"]
        ) {
            .enable(.`suppression fixture`)
        }
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.isEmpty)
    }

    @Test
    func `Manifest disabledRuleIDs threads through Driver to Configuration`() {
        // The Driver-level threading: a Manifest with disabledRuleIDs
        // produces a Configuration whose disabledRuleIDs carries the
        // same IDs.
        let manifest = Lint.Manifest(
            enabledRuleIDs: [],
            disabledRuleIDs: ["suppression fixture"]
        )
        let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
        #expect(configuration.disabledRuleIDs.contains("suppression fixture"))
    }
}

