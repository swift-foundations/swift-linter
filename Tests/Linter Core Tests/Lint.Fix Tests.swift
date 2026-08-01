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

import File_System
import Linter_Primitives
import SwiftSyntax
import Testing

@testable import Linter_Core

extension Lint.Fix {
    @Suite
    struct Test {
        @Suite struct `Fixture Scoping` {}
    }
}

extension Lint.Fix.Test.`Fixture Scoping` {
    private static func scoped(_ text: Swift.String) throws(Paths.Path.Error) -> Swift.Bool {
        Lint.Fix.isFixtureScoped(try File.Path(text))
    }

    @Test
    func `a file inside a fixtures directory is scoped out`() throws(Paths.Path.Error) {
        #expect(try Self.scoped("/pkg/Tests/Fixtures/wave-1-violations.swift"))
    }

    @Test
    func `a file nested deeper under a fixtures directory is scoped out`() throws(Paths.Path.Error) {
        #expect(try Self.scoped("/pkg/Tests/Fixtures/path-filter-fixture/Sources/A.swift"))
    }

    @Test
    func `a lowercase fixtures directory is scoped out`() throws(Paths.Path.Error) {
        #expect(try Self.scoped("/pkg/Tests/fixtures/A.swift"))
    }

    // The positive control this whole exemption class exists for. A
    // path-scoped check written with `contains` or a prefix test passes
    // every case above and fails exactly here — silently, on a real source
    // file that would then never be fixed again.
    @Test
    func `a bare file named Fixtures is still fixable`() throws(Paths.Path.Error) {
        #expect(try !Self.scoped("/pkg/Sources/Thing/Fixtures.swift"))
    }

    @Test
    func `a file named Fixtures with no extension is still fixable`() throws(Paths.Path.Error) {
        #expect(try !Self.scoped("/pkg/Sources/Thing/Fixtures"))
    }

    @Test
    func `a directory whose name merely starts with Fixtures is not scoped out`() throws(Paths.Path.Error) {
        #expect(try !Self.scoped("/pkg/Tests/FixturesSupport/A.swift"))
    }

    @Test
    func `a directory whose name merely contains Fixtures is not scoped out`() throws(Paths.Path.Error) {
        #expect(try !Self.scoped("/pkg/Tests/MyFixtures/A.swift"))
    }

    @Test
    func `an ordinary source path is not scoped out`() throws(Paths.Path.Error) {
        #expect(try !Self.scoped("/pkg/Sources/Thing/Thing.swift"))
    }
}

// A rewriter that would rewrite absolutely any file, so that a run which
// changes nothing can only be the scoping and never the rule.
extension Lint.Rule {
    fileprivate static let `always rewrites fixture` = Lint.Rule(
        id: "always rewrites fixture",
        default: .warning,
        findings: { _, _ in [] },
        fix: { source in source.tree.description + "// rewritten\n" }
    )
}

extension Lint.Fix.Test.`Fixture Scoping` {
    private static func fixturesRoot(
        testFile: Swift.String = #filePath
    ) throws(Paths.Path.Error) -> File.Path {
        var components: [Swift.String] =
            testFile
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(Swift.String.init)
        _ = components.popLast()  // "Lint.Fix Tests.swift"
        _ = components.popLast()  // "Linter Core Tests"
        components.append("Fixtures")
        return try File.Path(components.joined(separator: "/"))
    }

    // End to end, over this package's own fixtures tree — the very tree a
    // fleet fix run rewrote. The rewriter above fires on every file, so a
    // run reporting no changes AND no files scanned proves the gate sits
    // ahead of the rewriter rather than discarding its output afterwards.
    @Test
    func `a fix run over a fixtures tree rewrites nothing`() throws {
        let root = try Self.fixturesRoot()
        let configuration = Lint.Configuration {
            .enable(.`always rewrites fixture`)
        }
        let outcome = try Lint.Fix.apply(
            paths: [root],
            configuration: configuration,
            mode: .dryRun
        )
        #expect(outcome.fixableRules == 1)
        #expect(outcome.changes.isEmpty)
        #expect(outcome.filesScanned == 0)
    }
}
