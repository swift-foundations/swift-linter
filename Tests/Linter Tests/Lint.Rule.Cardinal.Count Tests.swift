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
import SwiftSyntax
import SwiftParser
@testable import Linter

extension Lint.Rule.Cardinal.Count {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Evasion {}
        @Suite struct Negative {}
    }
}

extension Lint.Rule.Cardinal.Count.Test {
    static func findings(in source: Swift.String, file: Swift.String = "test.swift") -> [Lint.Finding] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: file, filePath: file, content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        return Lint.Rule.Cardinal.Count().findings(in: parsed)
    }
}

extension Lint.Rule.Cardinal.Count.Test.Unit {
    @Test
    func `Bare count - 1 is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = count - 1")
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].identifier == "cardinal_count_minus_one")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `Member-access count - 1 is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = seq.count - 1")
        #expect(findings.count == 1)
    }

    @Test
    func `Custom severity is honored`() {
        let source = "let n = count - 1"
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "test.swift", tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: "test.swift", filePath: "test.swift", content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        let rule = Lint.Rule.Cardinal.Count(severity: .error)
        let findings = rule.findings(in: parsed)
        #expect(findings.count == 1)
        if findings.count == 1 {
            #expect(findings[0].severity == .error)
        }
    }
}

extension Lint.Rule.Cardinal.Count.Test.Evasion {
    @Test
    func `Paren-wrapped (count - 1) is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = (count - 1)")
        #expect(findings.count == 1)
    }

    @Test
    func `Cast-outside Double(seq.count) - 1 is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = Double(seq.count) - 1")
        #expect(findings.count == 1)
    }

    @Test
    func `Algebraic-flip i + 1 less-than count is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "if i + 1 < count { }")
        #expect(findings.count == 1)
    }

    @Test
    func `Algebraic-flip distance + 1 equals count is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "if distance + 1 == count { }")
        #expect(findings.count == 1)
    }

    @Test
    func `Algebraic-flip count greater-than i + 1 is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "if count > i + 1 { }")
        #expect(findings.count == 1)
    }

    @Test
    func `Algebraic-flip with 1 + i (commutative) is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "if 1 + i < count { }")
        #expect(findings.count == 1)
    }

    @Test
    func `Operand-reorder count - i - 1 is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = count - i - 1")
        #expect(findings.count >= 1)
    }

    @Test
    func `Comments-as-code is NOT flagged`() {
        let source = """
        // count - 1 is the canonical anti-pattern (this is just prose)
        let x = 42
        """
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: source)
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.Cardinal.Count.Test.Negative {
    @Test
    func `count - 2 is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = count - 2")
        #expect(findings.isEmpty)
    }

    @Test
    func `accountCount - 1 (non-count identifier) is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = accountCount - 1")
        #expect(findings.isEmpty)
    }

    @Test
    func `count + 1 is NOT flagged outside comparison context`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = count + 1")
        #expect(findings.isEmpty)
    }

    @Test
    func `i + 1 < limit is NOT flagged when count absent`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "if i + 1 < limit { }")
        #expect(findings.isEmpty)
    }

    @Test
    func `Empty file produces no findings`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "")
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.Cardinal.Count.Test.`Edge Case` {
    @Test
    func `count - 1 inside string literal is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: #"let s = "count - 1""#)
        #expect(findings.isEmpty)
    }

    @Test
    func `Nested expression let n = (a + b) + (count - 1) is flagged`() {
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: "let n = (a + b) + (count - 1)")
        #expect(findings.count == 1)
    }

    @Test
    func `Multi-line nested algebraic-flip is flagged`() {
        let source = """
        if i + 1
            < count {
            doSomething()
        }
        """
        let findings = Lint.Rule.Cardinal.Count.Test.findings(in: source)
        #expect(findings.count == 1)
    }
}
