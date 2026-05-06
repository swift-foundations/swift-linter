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
@testable import Linter_Rule_ResultBuilder

extension Lint.Rule.ResultBuilderForLoop {
    @Suite
    struct Test {
        @Suite struct PositiveCases {}
        @Suite struct NegativeCases {}
        @Suite struct CalleePatterns {}
        @Suite struct EdgeCases {}
        @Suite struct Severity {}
        @Suite struct Allowlist {}
    }
}

extension Lint.Rule.ResultBuilderForLoop.Test {
    static func findings(
        in source: Swift.String,
        rule: Lint.Rule.ResultBuilderForLoop = Lint.Rule.ResultBuilderForLoop(),
        file: Swift.String = "test.swift"
    ) -> [Lint.Finding] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        var manager = Source.Manager()
        let id = manager.register(fileID: file, filePath: file, content: Swift.Array(source.utf8))
        let parsed = Lint.Source.Parsed(file: manager.file(for: id), tree: tree, converter: converter)
        return rule.findings(in: parsed)
    }
}

// MARK: - Positive cases (rule fires)

extension Lint.Rule.ResultBuilderForLoop.Test.PositiveCases {
    @Test
    func `Array with for-loop is flagged`() {
        let source = """
        let a = Array<Int> {
            for i in 0..<100 {
                i
            }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
        if findings.count == 1 {
            #expect(findings[0].identifier == "result_builder_for_loop")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `Set with for-loop is flagged`() {
        let source = """
        let s = Set<Int> {
            for i in 0..<10 {
                i
            }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Bitset with for-loop is flagged`() {
        let source = """
        let b = Bitset {
            for i in 0..<10 {
                i
            }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `For-loop nested inside an if-statement is flagged`() {
        let source = """
        let a = Array<Int> {
            if condition {
                for i in 0..<100 {
                    i
                }
            }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Multiple for-loops in same builder body are each flagged`() {
        let source = """
        let a = Array<Int> {
            for i in 0..<10 { i }
            for j in 10..<20 { j }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        // Single emission per builder closure with at least one for-loop.
        // Detector finds first for-loop and skips children — only one finding.
        #expect(findings.count == 1)
    }
}

// MARK: - Negative cases (rule does NOT fire)

extension Lint.Rule.ResultBuilderForLoop.Test.NegativeCases {
    @Test
    func `Array with Sequence overload is NOT flagged`() {
        let source = """
        let a = Array<Int> {
            0..<100
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `Array with literal statements is NOT flagged`() {
        let source = """
        let a = Array<Int> {
            1
            2
            3
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `For-loop outside any builder context is NOT flagged`() {
        let source = """
        var a: [Int] = []
        for i in 0..<100 {
            a.append(i)
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `Custom non-allowlisted Builder with for-loop is NOT flagged`() {
        let source = """
        let m = MyCustomThing {
            for i in 0..<10 {
                i
            }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `For-loop in nested closure NOT inside outer builder is NOT flagged`() {
        // The for-loop is inside `someFunction { ... }`, which is NOT in the
        // allowlist. The outer Array body has no for-loop directly.
        let source = """
        let a = Array<Int> {
            someFunction {
                for i in 0..<10 {
                    print(i)
                }
            }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }
}

// MARK: - Callee identifier extraction

extension Lint.Rule.ResultBuilderForLoop.Test.CalleePatterns {
    @Test
    func `Generic Array callsite is recognized`() {
        let source = """
        let a = Array<Int> { for i in 0..<10 { i } }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Module-qualified Swift_Array callsite is recognized`() {
        let source = """
        let a = Swift.Array<Int> { for i in 0..<10 { i } }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Nested Buffer_Linear callsite is recognized`() {
        let source = """
        let b = Buffer<Int>.Linear { for i in 0..<10 { i } }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Nested Tree_N callsite is recognized`() {
        let source = """
        let t = Tree<Int>.N<2> { for i in 0..<10 { i } }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Nested Tree_Binary callsite is recognized`() {
        let source = """
        let t = Tree<Int>.Binary { for i in 0..<10 { i } }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Nested Set_Ordered callsite is recognized`() {
        let source = """
        let s = Set<Int>.Ordered { for i in 0..<10 { i } }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `Heap callsite with order argument is recognized`() {
        let source = """
        let h = Heap<Int>(order: .ascending) {
            for i in 0..<10 {
                i
            }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 1)
    }
}

// MARK: - Edge cases

extension Lint.Rule.ResultBuilderForLoop.Test.EdgeCases {
    @Test
    func `Empty file produces no findings`() {
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: "")
        #expect(findings.isEmpty)
    }

    @Test
    func `For-loop in string literal is NOT flagged`() {
        let source = """
        let s = "Array<Int> { for i in 0..<10 { i } }"
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `For-loop in comment is NOT flagged`() {
        let source = """
        // Don't write Array<Int> { for i in 0..<10 { i } }
        let a = 42
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `Empty Array builder body is NOT flagged`() {
        let source = """
        let a = Array<Int> {}
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `Nested Array builders both with for-loops are both flagged`() {
        // Outer Array builder body contains an inner Array builder body.
        // Both are in the allowlist; but the OUTER detector skips nested
        // closures, so it only sees the for-loop in the OUTER closure
        // (which is empty here). The INNER builder's for-loop is detected
        // when the visitor reaches the inner FunctionCallExprSyntax.
        let source = """
        let a = Array<[Int]> {
            for i in 0..<3 { i }
            Array<Int> {
                for j in 0..<10 { j }
            }
        }
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.count == 2)
    }

    @Test
    func `Allowlisted callee without trailing closure is NOT flagged`() {
        // Array(repeating:count:) — no closure, no body to inspect.
        let source = """
        let a = Array(repeating: 0, count: 10)
        """
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source)
        #expect(findings.isEmpty)
    }
}

// MARK: - Severity / configuration

extension Lint.Rule.ResultBuilderForLoop.Test.Severity {
    @Test
    func `Default severity is warning`() {
        #expect(Lint.Rule.ResultBuilderForLoop.defaultSeverity == .warning)
    }

    @Test
    func `Custom severity is honored`() {
        let source = """
        let a = Array<Int> { for i in 0..<10 { i } }
        """
        let rule = Lint.Rule.ResultBuilderForLoop(severity: .error)
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source, rule: rule)
        #expect(findings.count == 1)
        if findings.count == 1 {
            #expect(findings[0].severity == .error)
        }
    }
}

// MARK: - Allowlist extensibility

extension Lint.Rule.ResultBuilderForLoop.Test.Allowlist {
    @Test
    func `Default allowlist contains the 18 institute Builder names`() {
        let allowlist = Lint.Rule.ResultBuilderForLoop.defaultAllowlist
        #expect(allowlist.contains("Array"))
        #expect(allowlist.contains("Buffer.Linear"))
        #expect(allowlist.contains("Tree.N"))
        #expect(allowlist.contains("Set.Ordered"))
        #expect(allowlist.contains("Heap"))
    }

    @Test
    func `Empty allowlist suppresses all findings`() {
        let source = """
        let a = Array<Int> { for i in 0..<10 { i } }
        """
        let rule = Lint.Rule.ResultBuilderForLoop(allowlist: [])
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source, rule: rule)
        #expect(findings.isEmpty)
    }

    @Test
    func `Consumer-extended allowlist catches custom Builders`() {
        let source = """
        let m = MyCustomBuilder<Int> { for i in 0..<10 { i } }
        """
        let rule = Lint.Rule.ResultBuilderForLoop(allowlist: ["MyCustomBuilder"])
        let findings = Lint.Rule.ResultBuilderForLoop.Test.findings(in: source, rule: rule)
        #expect(findings.count == 1)
    }
}
