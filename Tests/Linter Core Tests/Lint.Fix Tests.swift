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
        @Suite struct `Target Scoping` {}
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
    // run reporting no changes while still counting the files proves
    // detection remains visible and the gate sits ahead of the rewriter
    // rather than discarding its output afterwards.
    @Test
    func `a fix run over a fixtures tree rewrites nothing`() throws {
        let root = try Self.fixturesRoot()
        let configuration = Lint.Configuration {
            .enable(.`always rewrites fixture`)
        }
        let outcome = try Lint.Fix.apply(
            paths: [root],
            targets: [root],
            configuration: configuration,
            mode: .dryRun
        )
        #expect(outcome.fixableRules == 1)
        #expect(outcome.changes.isEmpty)
        #expect(outcome.filesScanned > 0)
    }
}

extension Lint.Rule {
    fileprivate static let `always rewrites target` = Lint.Rule(
        id: "always rewrites target",
        default: .warning,
        findings: { source, severity in
            [
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.file.fileID,
                        filePath: source.file.filePath,
                        line: 1,
                        column: 1
                    ),
                    severity: severity,
                    identifier: "always rewrites target",
                    message: "target-scope fixture fired"
                )
            ]
        },
        fix: { source in source.tree.description + "// rewritten\n" }
    )
}

extension Lint.Fix.Test.`Target Scoping` {
    private static func write(
        _ text: Swift.String,
        at path: File.Path
    ) throws {
        guard let parent = path.parent else { return }
        try File.Directory(parent).create.recursive()
        try File(path).write.atomic(text)
    }

    private static func fixture() throws -> (
        root: File.Path,
        target: File.Path,
        originals: [(path: File.Path, text: Swift.String)]
    ) {
        let key = Swift.String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16)
        let root = try File.Path.Temporary.deterministic(
            prefix: "lint-fix-targets-",
            key: key,
            suffix: ""
        )
        let target = root / "Sources" / "Declared"
        let originals: [(path: File.Path, text: Swift.String)] = [
            (root / "Package.swift", "import PackageDescription\n"),
            (target / "Target.swift", "struct Target {}\n"),
            (root / "Sources" / "DeclaredSupport" / "NearMiss.swift", "struct NearMiss {}\n"),
            (root / "Scripts" / "tool.swift", "import Foundation\n"),
            (root / "Tests" / "Fixtures" / "input.swift", "struct Fixture {}\n"),
            (root / "Other" / "Other.swift", "struct Other {}\n"),
        ]
        for original in originals {
            try Self.write(original.text, at: original.path)
        }
        return (root: root, target: target, originals: originals)
    }

    @Test
    func `declared target roots constrain application without hiding detection`() throws {
        let fixture = try Self.fixture()
        let configuration = Lint.Configuration {
            .enable(.`always rewrites target`)
        }

        let findings = try Lint.Run.run(
            paths: [fixture.root],
            configuration: configuration
        )
        #expect(findings.count == fixture.originals.count)
        let detected = Swift.Set(findings.compactMap(\.record.location.filePath))
        for original in fixture.originals {
            #expect(detected.contains(original.path.string))
        }
        #expect(configuration.rules.effective.entries.count == 1)

        let outcome = try Lint.Fix.apply(
            paths: [fixture.root],
            targets: [fixture.target],
            configuration: configuration,
            mode: .apply
        )

        #expect(outcome.filesScanned == fixture.originals.count)
        #expect(outcome.changes.map(\.path) == [fixture.target / "Target.swift"])
        for original in fixture.originals {
            let current = try Lint.File.Single.contents(of: original.path)
            if original.path == fixture.target / "Target.swift" {
                #expect(current == original.text + "// rewritten\n")
            } else {
                #expect(current == original.text)
            }
        }
    }

    @Test
    func `an empty target vector applies nothing`() throws {
        let fixture = try Self.fixture()
        let configuration = Lint.Configuration {
            .enable(.`always rewrites target`)
        }
        let outcome = try Lint.Fix.apply(
            paths: [fixture.root],
            targets: [],
            configuration: configuration,
            mode: .apply
        )
        #expect(outcome.changes.isEmpty)
        for original in fixture.originals {
            #expect(try Lint.File.Single.contents(of: original.path) == original.text)
        }
    }
}
