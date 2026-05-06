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

extension Lint.Rule.Cardinal.Constructor {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Negative {}
    }
}

extension Lint.Rule.Cardinal.Constructor.Test {
    static func findings(in source: Swift.String, file: Swift.String = "test.swift") -> [Lint.Finding] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: file, filePath: file, content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        return Lint.Rule.Cardinal.Constructor().findings(in: parsed)
    }
}

extension Lint.Rule.Cardinal.Constructor.Test.Unit {
    @Test
    func `Cardinal(0) is flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "let c = Cardinal(0)")
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].identifier == "cardinal_zero_one_constructor")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `Cardinal(1) is flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "let c = Cardinal(1)")
        #expect(findings.count == 1)
    }

    @Test
    func `Cardinal.init(0) is flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "let c = Cardinal.init(0)")
        #expect(findings.count == 1)
    }
}

extension Lint.Rule.Cardinal.Constructor.Test.Negative {
    @Test
    func `Cardinal(2) is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "let c = Cardinal(2)")
        #expect(findings.isEmpty)
    }

    @Test
    func `Cardinal(_unchecked, 0) (multi-arg) is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "let c = Cardinal(unchecked: 0)")
        #expect(findings.isEmpty)
    }

    @Test
    func `Cardinal(rawValue: 0) (labeled arg) is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "let c = Cardinal(rawValue: 0)")
        #expect(findings.isEmpty)
    }

    @Test
    func `Other type with literal 0 is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "let i = Int(0)")
        #expect(findings.isEmpty)
    }

    @Test
    func `Cardinal.zero (canonical accessor) is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "let c = Cardinal.zero")
        #expect(findings.isEmpty)
    }

    @Test
    func `Cardinal in string literal is NOT flagged`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: #"let s = "Cardinal(0)""#)
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.Cardinal.Constructor.Test.`Edge Case` {
    @Test
    func `Multi-line Cardinal with newline-arg is flagged`() {
        let source = """
        let c = Cardinal(
            0
        )
        """
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Custom severity is honored`() {
        let source = "let c = Cardinal(0)"
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "test.swift", tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: "test.swift", filePath: "test.swift", content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        let rule = Lint.Rule.Cardinal.Constructor(severity: .error)
        let findings = rule.findings(in: parsed)
        #expect(findings.count == 1)
        if findings.count == 1 {
            #expect(findings[0].severity == .error)
        }
    }

    @Test
    func `Empty file produces no findings`() {
        let findings = Lint.Rule.Cardinal.Constructor.Test.findings(in: "")
        #expect(findings.isEmpty)
    }
}
