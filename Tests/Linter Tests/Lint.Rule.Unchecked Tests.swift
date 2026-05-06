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
import Linter_Rule_Unchecked

extension Lint.Rule.Unchecked {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
    }
}

extension Lint.Rule.Unchecked.Test {
    static func findings(in source: String, file: String = "test.swift") -> [Lint.Finding] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: file, filePath: file, content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        return Lint.Rule.Unchecked().findings(in: parsed)
    }
}

extension Lint.Rule.Unchecked.Test.Unit {
    @Test
    func `Call site with __unchecked label is flagged`() {
        let source = "let x = Foo(__unchecked: ())"
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].identifier == "unchecked_call_site")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `Declaration site with __unchecked parameter is NOT flagged`() {
        let source = """
        struct Foo {
            init(__unchecked _: ()) {}
        }
        """
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `Other argument labels are NOT flagged`() {
        let source = "let x = Foo(name: 42, value: \"abc\")"
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `Multiple call sites are all flagged`() {
        let source = """
        let a = Foo(__unchecked: (), value: 1)
        let b = Bar(other: 2, __unchecked: ())
        let c = Baz(__unchecked: ())
        """
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.count == 3)
    }

    @Test
    func `Mixed declaration AND call sites flag only call sites`() {
        let source = """
        struct Foo {
            init(__unchecked _: ()) {}
        }

        let x = Foo(__unchecked: ())
        """
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Custom severity is honored`() {
        let source = "let x = Foo(__unchecked: ())"
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "test.swift", tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: "test.swift", filePath: "test.swift", content: Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        let rule = Lint.Rule.Unchecked(severity: .error)
        let findings = rule.findings(in: parsed)
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].severity == .error)
        }
    }
}

extension Lint.Rule.Unchecked.Test.`Edge Case` {
    @Test
    func `Nested call site with __unchecked is flagged`() {
        let source = "let x = outer(inner: Foo(__unchecked: ()))"
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Generic call site with __unchecked is flagged`() {
        let source = "let x = Foo<Int>(__unchecked: ())"
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Trailing closure call with __unchecked label is flagged`() {
        let source = """
        let x = Foo(__unchecked: ()) { value in
            value + 1
        }
        """
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `__unchecked appearing in a string literal is NOT flagged`() {
        let source = "let x = \"Foo(__unchecked: ())\""
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `__unchecked in a comment is NOT flagged`() {
        let source = """
        // Foo(__unchecked: ()) is the canonical anti-pattern
        let x = 42
        """
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `__unchecked as part of a larger label is NOT flagged`() {
        let source = "let x = Foo(__unchecked_extra: ())"
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `Static method call site with __unchecked is flagged`() {
        let source = "let x = Foo.make(__unchecked: ())"
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `self.init call site with __unchecked is flagged`() {
        let source = """
        struct Foo {
            init(value: Int) {
                self.init(__unchecked: ())
            }
            init(__unchecked _: ()) {}
        }
        """
        let findings = Lint.Rule.Unchecked.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Empty file produces no findings`() {
        let findings = Lint.Rule.Unchecked.Test.findings(in: "")
        #expect(findings.isEmpty)
    }
}
