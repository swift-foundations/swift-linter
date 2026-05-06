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

extension Lint.Rule.RawValue.BitPattern {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Evasion {}
        @Suite struct Negative {}
    }
}

extension Lint.Rule.RawValue.BitPattern.Test {
    static func findings(in source: Swift.String, file: Swift.String = "test.swift") -> [Lint.Finding] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: file, filePath: file, content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        return Lint.Rule.RawValue.BitPattern().findings(in: parsed)
    }
}

extension Lint.Rule.RawValue.BitPattern.Test.Unit {
    @Test
    func `Int(bitPattern: x.rawValue) is flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: "let i = Int(bitPattern: x.rawValue)")
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].identifier == "bitpattern_rawvalue_chain")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `UInt(bitPattern: x.rawValue) is flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: "let i = UInt(bitPattern: x.rawValue)")
        #expect(findings.count == 1)
    }
}

extension Lint.Rule.RawValue.BitPattern.Test.Evasion {
    @Test
    func `Int.init(bitPattern: x.rawValue) (typename-swap via .init) is flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(
            in: "let i = Int.init(bitPattern: x.rawValue)"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `self.init(bitPattern: x.rawValue) (typename-swap via self) is flagged`() {
        let source = """
        struct W {
            init(value: X) {
                self.init(bitPattern: value.rawValue)
            }
            init(bitPattern: Int) {}
        }
        """
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Int8(bitPattern: x.rawValue) (sized integer typename-swap) is flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(
            in: "let i = Int8(bitPattern: x.rawValue)"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `Nested rawValue Int(bitPattern: foo.bar.rawValue) is flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(
            in: "let i = Int(bitPattern: foo.bar.rawValue)"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `Subscript Int(bitPattern: arr[i].rawValue) is flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(
            in: "let i = Int(bitPattern: arr[i].rawValue)"
        )
        #expect(findings.count == 1)
    }
}

extension Lint.Rule.RawValue.BitPattern.Test.Negative {
    @Test
    func `Int(bitPattern: typedValue) (no rawValue chain) is NOT flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: "let i = Int(bitPattern: cardinal)")
        #expect(findings.isEmpty)
    }

    @Test
    func `Int(bitPattern: foo.bar) (non-rawValue member) is NOT flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: "let i = Int(bitPattern: foo.bar)")
        #expect(findings.isEmpty)
    }

    @Test
    func `Int(other: x.rawValue) (different label) is NOT flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: "let i = Int(other: x.rawValue)")
        #expect(findings.isEmpty)
    }

    @Test
    func `Int(x.rawValue) (no bitPattern label) is NOT flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: "let i = Int(x.rawValue)")
        #expect(findings.isEmpty)
    }

    @Test
    func `Comment containing the pattern is NOT flagged`() {
        let source = """
        // Int(bitPattern: x.rawValue) is the canonical anti-pattern
        let y = 42
        """
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `String literal containing the pattern is NOT flagged`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(
            in: #"let s = "Int(bitPattern: x.rawValue)""#
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `Empty file produces no findings`() {
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: "")
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.RawValue.BitPattern.Test.`Edge Case` {
    @Test
    func `Multi-line Int(bitPattern: ... rawValue) is flagged`() {
        let source = """
        let i = Int(
            bitPattern: x.rawValue
        )
        """
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Multiple bitPattern calls each flagged`() {
        let source = """
        let a = Int(bitPattern: x.rawValue)
        let b = UInt(bitPattern: y.rawValue)
        """
        let findings = Lint.Rule.RawValue.BitPattern.Test.findings(in: source)
        #expect(findings.count == 2)
    }

    @Test
    func `Custom severity is honored`() {
        let source = "let i = Int(bitPattern: x.rawValue)"
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "test.swift", tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: "test.swift", filePath: "test.swift", content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        let rule = Lint.Rule.RawValue.BitPattern(severity: .error)
        let findings = rule.findings(in: parsed)
        #expect(findings.count == 1)
        if findings.count == 1 {
            #expect(findings[0].severity == .error)
        }
    }
}
