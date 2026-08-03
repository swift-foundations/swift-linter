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
        @Suite struct Application {}
        @Suite struct Exclusion {}
        @Suite struct `Manifest Scope` {}
    }
}

extension Lint.Fix.Test.Application {
    private static func root() throws(Paths.Path.Error) -> File.Path {
        try File.Path.Temporary.deterministic(
            prefix: "lint-fix-application-",
            key: Swift.String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16),
            suffix: ""
        )
    }

    private static func write(_ text: Swift.String, at path: File.Path) throws {
        if let parent = path.parent {
            try File.Directory(parent).create.recursive()
        }
        try File(path).write.atomic(text)
    }

    private static func contents(_ path: File.Path) throws -> Swift.String {
        try Lint.File.Single.contents(of: path)
    }

    private static func bytes(_ path: File.Path) throws -> [Byte] {
        try File(path).read.full { (span: Swift.Span<Byte>) in
            var copy: [Byte] = []
            copy.reserveCapacity(span.count)
            span.indices.forEach { copy.append(span[$0]) }
            return copy
        }
    }

    private static func remove(_ path: File.Path) {
        do throws(File.System.Delete.Error) {
            try File.System.Delete.delete(at: path, recursive: true)
        } catch {}
    }

    @Test
    func `a later scan failure leaves an earlier planned fix unapplied`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let target = root / "Sources" / "Target"
        let first = target / "A.swift"
        let invalid = target / "Z.swift"
        try Self.write("struct First {}\n", at: first)
        try File(invalid).write.atomic(contentsOf: [0xFF] as [Byte])
        let configuration = Lint.Configuration {
            .enable(.`always rewrites target`)
        }

        do throws(Lint.Run.Error) {
            _ = try Lint.Fix.apply(
                paths: [root],
                targets: [target],
                configuration: configuration,
                mode: .apply
            )
            Issue.record("expected the invalid UTF-8 source to abort the scan")
        } catch let error {
            #expect(error == .nonUTF8(path: invalid))
        }

        #expect(try Self.contents(first) == "struct First {}\n")
        #expect(try Self.bytes(invalid) == [0xFF] as [Byte])
    }

    @Test
    func `a stale original is refused before its publication`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let target = root / "Sources" / "Target"
        let stale = target / "Stale.swift"
        try Self.write("struct ConcurrentEdit {}\n", at: stale)
        let change = Lint.Fix.Change(
            path: stale,
            rules: [],
            original: "struct Original {}\n",
            fixed: "struct Planned {}\n"
        )

        do throws(Lint.Run.Error) {
            _ = try Lint.Fix.Publisher.apply([change])
            Issue.record("expected the stale content identity to be rejected")
        } catch let error {
            #expect(
                error
                    == .staleFixOriginal(
                        path: stale,
                        planned: [stale],
                        published: []
                    )
            )
        }

        #expect(try Self.contents(stale) == "struct ConcurrentEdit {}\n")
    }

    @Test
    func `the outcome exposes the exact changed path plan`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let target = root / "Sources" / "Target"
        let first = target / "A.swift"
        let second = target / "B.swift"
        try Self.write("struct First {}\n", at: first)
        try Self.write("struct Second {}\n", at: second)
        let configuration = Lint.Configuration {
            .enable(.`always rewrites target`)
        }

        let outcome = try Lint.Fix.apply(
            paths: [root],
            targets: [target],
            configuration: configuration,
            mode: .dryRun
        )

        #expect(outcome.paths == [first, second])
        #expect(outcome.published.isEmpty)
    }

    @Test
    func `a late parse refusal leaves the complete plan unpublished`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let target = root / "Sources" / "Target"
        let first = target / "A.swift"
        let invalid = target / "Z.swift"
        try Self.write("struct First {}\n", at: first)
        try Self.write("struct Invalid {}\n", at: invalid)
        let configuration = Lint.Configuration {
            .enable(.`fails parsing late`)
        }

        let outcome = try Lint.Fix.apply(
            paths: [root],
            targets: [target],
            configuration: configuration,
            mode: .apply
        )

        #expect(outcome.paths == [first])
        #expect(outcome.published.isEmpty)
        #expect(outcome.refusals.map(\.path) == [invalid])
        #expect(try Self.contents(first) == "struct First {}\n")
        #expect(try Self.contents(invalid) == "struct Invalid {}\n")
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

    fileprivate static let `rewrites target once` = Lint.Rule(
        id: "rewrites target once",
        default: .warning,
        findings: { _, _ in [] },
        fix: { source in
            guard source.tree.description == "struct Original {}\n" else { return nil }
            return "struct Fixed {}\n"
        }
    )

    fileprivate static let `fails parsing late` = Lint.Rule(
        id: "fails parsing late",
        default: .warning,
        findings: { _, _ in [] },
        fix: { source in
            if source.tree.description == "struct Invalid {}\n" {
                return "struct Broken {"
            }
            return source.tree.description + "// rewritten\n"
        }
    )

    fileprivate static let `shadowed standard name` = Lint.Rule(
        id: "shadowed standard name",
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
                    identifier: "shadowed standard name",
                    message: "shadow-risk fixture fired"
                )
            ]
        },
        fix: { source in
            guard source.tree.description == "struct Original {}\n" else { return nil }
            return "struct Shadowed {}\n"
        }
    )

    fileprivate static let `loop idiom` = Lint.Rule(
        id: "loop idiom",
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
                    identifier: "loop idiom",
                    message: "loop-fixer fixture fired"
                )
            ]
        },
        fix: { source in
            guard source.tree.description == "struct Original {}\n" else { return nil }
            return "struct Looped {}\n"
        }
    )
}

extension Lint.Fix.Test.Exclusion {
    private static func root() throws(Paths.Path.Error) -> File.Path {
        try File.Path.Temporary.deterministic(
            prefix: "lint-fix-exclusion-",
            key: Swift.String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16),
            suffix: ""
        )
    }

    private static func write(_ text: Swift.String, at path: File.Path) throws {
        if let parent = path.parent {
            try File.Directory(parent).create.recursive()
        }
        try File(path).write.atomic(text)
    }

    private static func remove(_ path: File.Path) {
        do throws(File.System.Delete.Error) {
            try File.System.Delete.delete(at: path, recursive: true)
        } catch {}
    }

    private static func configuration() -> Lint.Configuration {
        Lint.Configuration {
            Lint.Rule.Configuration.enable(.`shadowed standard name`)
            Lint.Rule.Configuration.enable(.`loop idiom`)
        }
    }

    @Test
    func `excluding a shadow-risk rule preserves detection and applies the unrelated loop fixer`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let target = root / "Sources" / "Target"
        let file = target / "Target.swift"
        try Self.write("struct Original {}\n", at: file)
        let configuration = Self.configuration()

        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(Set(findings.map(\.record.identifier)) == ["shadowed standard name", "loop idiom"])

        let outcome = try Lint.Fix.apply(
            paths: [root],
            targets: [target],
            configuration: configuration,
            excluding: ["shadowed standard name"],
            mode: .apply
        )

        #expect(outcome.excludedRules == ["shadowed standard name"])
        #expect(outcome.plannedRules == ["loop idiom"])
        #expect(outcome.paths == [file])
        #expect(outcome.published == [file])
        #expect(try Lint.File.Single.contents(of: file) == "struct Looped {}\n")
    }

    @Test
    func `multiple duplicate and unknown exclusions publish no files when no fixer remains`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let target = root / "Sources" / "Target"
        let file = target / "Target.swift"
        try Self.write("struct Original {}\n", at: file)

        let exclusions: Set<Lint.Rule.ID> = [
            "shadowed standard name",
            "loop idiom",
            "loop idiom",
            "not installed here",
        ]
        let outcome = try Lint.Fix.apply(
            paths: [root],
            targets: [target],
            configuration: Self.configuration(),
            excluding: exclusions,
            mode: .apply
        )

        #expect(outcome.excludedRules == ["shadowed standard name", "loop idiom"])
        #expect(outcome.plannedRules.isEmpty)
        #expect(outcome.paths.isEmpty)
        #expect(outcome.published.isEmpty)
        #expect(try Lint.File.Single.contents(of: file) == "struct Original {}\n")
    }
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
        #expect(outcome.paths == [fixture.target / "Target.swift"])
        #expect(outcome.published == [fixture.target / "Target.swift"])
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

extension Lint.Fix.Test.Application {
    @Test
    func `applying the same fix again is idempotent`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let target = root / "Sources" / "Target"
        let file = target / "Target.swift"
        try Self.write("struct Original {}\n", at: file)
        let configuration = Lint.Configuration {
            .enable(.`rewrites target once`)
        }

        let first = try Lint.Fix.apply(
            paths: [root],
            targets: [target],
            configuration: configuration,
            mode: .apply
        )
        let second = try Lint.Fix.apply(
            paths: [root],
            targets: [target],
            configuration: configuration,
            mode: .apply
        )

        #expect(first.paths == [file])
        #expect(first.published == [file])
        #expect(second.paths.isEmpty)
        #expect(second.published.isEmpty)
        #expect(try Self.contents(file) == "struct Fixed {}\n")
    }
}

// MARK: - Manifest Scope (swift-foundations/swift-linter#32)
//
// A single source of truth for the fixture manifest text, shared between
// what a test writes to disk and what each fileprivate rule below compares
// against, so the two can never drift out of byte-for-byte agreement — the
// same discipline the file's other synthetic rules already rely on
// (`"struct Original {}\n"` compared verbatim). Both spawn a REAL
// `swift package dump-package` subprocess via
// `Lint.Fix.Scope.Manifest.evaluates(_:)`, precedented by this same test
// target's `Lint.File.Single.Runner Tests.swift`, which already spawns a
// real prebuilt-runner process.

fileprivate let manifestScopeOriginal = """
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Original"
)

"""

fileprivate let manifestScopeRewritten = """
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Rewritten"
)

"""

// Re-parses cleanly (a bare identifier is syntactically a valid
// expression) but fails SwiftPM's manifest evaluation: `swiftc` cannot
// resolve `undefinedIdentifierReference`, so `dump-package` exits
// non-zero. Verified against the installed toolchain before being chosen
// as the fixture — the concrete class re-parse structurally cannot catch.
fileprivate let manifestScopeCorrupted = """
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: undefinedIdentifierReference
)

"""

extension Lint.Rule {
    fileprivate static let `rewrites manifest name` = Lint.Rule(
        id: "rewrites manifest name",
        default: .warning,
        findings: { _, _ in [] },
        fix: { source in
            guard source.tree.description == manifestScopeOriginal else { return nil }
            return manifestScopeRewritten
        }
    )

    fileprivate static let `corrupts manifest name` = Lint.Rule(
        id: "corrupts manifest name",
        default: .warning,
        findings: { _, _ in [] },
        fix: { source in
            guard source.tree.description == manifestScopeOriginal else { return nil }
            return manifestScopeCorrupted
        }
    )
}

extension Lint.Fix.Test.`Manifest Scope` {
    private static func root() throws(Paths.Path.Error) -> File.Path {
        try File.Path.Temporary.deterministic(
            prefix: "lint-fix-manifest-scope-",
            key: Swift.String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16),
            suffix: ""
        )
    }

    private static func write(_ text: Swift.String, at path: File.Path) throws {
        if let parent = path.parent {
            try File.Directory(parent).create.recursive()
        }
        try File(path).write.atomic(text)
    }

    private static func contents(_ path: File.Path) throws -> Swift.String {
        try Lint.File.Single.contents(of: path)
    }

    private static func remove(_ path: File.Path) {
        do throws(File.System.Delete.Error) {
            try File.System.Delete.delete(at: path, recursive: true)
        } catch {}
    }
}

extension Lint.Fix.Test.`Manifest Scope` {
    // Fixture required by #32: a manifest finding whose fix applies end to
    // end. `manifest:` admits the exact `Package.swift` path even though it
    // sits outside every declared target root; the rewrite re-parses AND
    // evaluates, so it publishes exactly like an ordinary target-scoped fix.
    @Test
    func `a manifest fix applies end to end`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let manifest = root / "Package.swift"
        try Self.write(manifestScopeOriginal, at: manifest)
        let configuration = Lint.Configuration {
            .enable(.`rewrites manifest name`)
        }

        let outcome = try Lint.Fix.apply(
            paths: [root],
            targets: [],
            configuration: configuration,
            mode: .apply,
            manifest: manifest
        )

        #expect(outcome.paths == [manifest])
        #expect(outcome.published == [manifest])
        #expect(outcome.refusals.isEmpty)
        #expect(try Self.contents(manifest) == manifestScopeRewritten)
    }

    // Fixture required by #32: a corrupted-rewrite fixture that must refuse
    // rather than write. The rewrite re-parses (SwiftParser has no semantic
    // phase) but fails `swift package dump-package` evaluation, so the
    // manifest-scope guard — strictly stronger than the ordinary re-parse
    // guard — refuses it. The refusal blocks the WHOLE plan, the same
    // discipline an ordinary unparseable-rewrite refusal already has: an
    // otherwise-valid, co-planned change to an unrelated target file in the
    // SAME run is also left unpublished.
    @Test
    func `a manifest rewrite that fails evaluation is refused rather than written`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let manifest = root / "Package.swift"
        try Self.write(manifestScopeOriginal, at: manifest)
        let target = root / "Sources" / "Target"
        let sibling = target / "Sibling.swift"
        try Self.write("struct First {}\n", at: sibling)
        let configuration = Lint.Configuration {
            Lint.Rule.Configuration.enable(.`corrupts manifest name`)
            Lint.Rule.Configuration.enable(.`always rewrites target`)
        }

        let outcome = try Lint.Fix.apply(
            paths: [root],
            targets: [target],
            configuration: configuration,
            mode: .apply,
            manifest: manifest
        )

        #expect(outcome.published.isEmpty)
        #expect(outcome.refusals.map(\.path) == [manifest])
        #expect(outcome.refusals.map(\.reason) == [.manifestEvaluationFailed])
        #expect(try Self.contents(manifest) == manifestScopeOriginal)
        #expect(try Self.contents(sibling) == "struct First {}\n")
    }

    // A manifest path that is never supplied as `manifest:` stays excluded
    // exactly as it always has (the pre-#32, `targets`-only behavior) — the
    // positive control this whole scope exists to extend, not replace.
    @Test
    func `an unsupplied manifest scope leaves Package_swift untouched`() throws {
        let root = try Self.root()
        defer { Self.remove(root) }
        let manifest = root / "Package.swift"
        try Self.write(manifestScopeOriginal, at: manifest)
        let configuration = Lint.Configuration {
            .enable(.`rewrites manifest name`)
        }

        let outcome = try Lint.Fix.apply(
            paths: [root],
            targets: [],
            configuration: configuration,
            mode: .apply
        )

        #expect(outcome.changes.isEmpty)
        #expect(try Self.contents(manifest) == manifestScopeOriginal)
    }
}
