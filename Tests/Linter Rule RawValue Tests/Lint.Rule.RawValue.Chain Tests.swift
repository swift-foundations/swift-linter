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
import Linter_Primitives
@testable import Linter_Rule_RawValue

extension Lint.Rule.RawValue.Chain {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Evasion {}
        @Suite struct Negative {}
    }
}

extension Lint.Rule.RawValue.Chain.Test {
    static func findings(in source: Swift.String, file: Swift.String = "test.swift") -> [Lint.Finding] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: file, filePath: file, content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        return Lint.Rule.RawValue.Chain().findings(in: parsed)
    }
}

extension Lint.Rule.RawValue.Chain.Test.Unit {
    @Test
    func `x.rawValue.foo is flagged`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: "let n = x.rawValue.foo")
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].identifier == "chained_rawvalue_access")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `x.rawValue.foo() is flagged`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: "let n = x.rawValue.foo()")
        #expect(findings.count == 1)
    }
}

extension Lint.Rule.RawValue.Chain.Test.Evasion {
    @Test
    func `Paren-wrapped (x.rawValue).foo is flagged`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: "let n = (x.rawValue).foo")
        #expect(findings.count == 1)
    }

    @Test
    func `Double-paren ((x.rawValue)).foo is flagged`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: "let n = ((x.rawValue)).foo")
        #expect(findings.count == 1)
    }
}

extension Lint.Rule.RawValue.Chain.Test.Negative {
    @Test
    func `Bare x.rawValue (terminal access) is NOT flagged`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: "let n = x.rawValue")
        #expect(findings.isEmpty)
    }

    @Test
    func `x.rawValue inside string literal is NOT flagged`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: #"let s = "x.rawValue.foo""#)
        #expect(findings.isEmpty)
    }

    @Test
    func `x.foo.rawValue (rawValue at end of chain) is NOT flagged`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: "let n = x.foo.rawValue")
        #expect(findings.isEmpty)
    }

    @Test
    func `Empty file produces no findings`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: "")
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.RawValue.Chain.Test.`Edge Case` {
    @Test
    func `x.rawValue in comment is NOT flagged`() {
        let source = """
        // x.rawValue.foo is the canonical anti-pattern
        let y = 42
        """
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `Nested chain a.b.rawValue.c is flagged`() {
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: "let n = a.b.rawValue.c")
        #expect(findings.count == 1)
    }

    @Test
    func `Multiple chained accesses each flagged`() {
        let source = """
        let a = x.rawValue.foo
        let b = y.rawValue.bar
        """
        let findings = Lint.Rule.RawValue.Chain.Test.findings(in: source)
        #expect(findings.count == 2)
    }

    @Test
    func `Custom severity is honored`() {
        let source = "let n = x.rawValue.foo"
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "test.swift", tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: "test.swift", filePath: "test.swift", content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        let rule = Lint.Rule.RawValue.Chain(severity: .error)
        let findings = rule.findings(in: parsed)
        #expect(findings.count == 1)
        if findings.count == 1 {
            #expect(findings[0].severity == .error)
        }
    }
}
