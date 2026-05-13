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
import File_System
import Linter_Primitives
@testable import Linter_Core

extension Lint.Run {
    @Suite
    struct Test {
        @Suite struct Integration {}
    }
}

// Engine-level path-filter tests use a synthetic fixture rule constructed
// inline; the engine package has no dependency on any rule pack. The rule
// fires once per visited source file, which is sufficient signal to
// validate the `Lint.Filter` discrimination paths.
extension Lint.Rule {
    fileprivate static let `test fixture` = Lint.Rule(
        id: "test fixture",
        default: .warning,
        findings: { source, severity in
            [Diagnostic.Record(
                location: Source.Location(
                    fileID: source.file.fileID,
                    filePath: source.file.filePath,
                    line: 1,
                    column: 1
                ),
                severity: severity,
                identifier: "test fixture",
                message: "fixture rule fired"
            )]
        }
    )
}

// MARK: - Path filter integration
//
// Engine-layer integration coverage for the per-rule
// `Lint.Rule.Configuration.paths` filter (`Lint.Filter`). The fixture
// at `Tests/Fixtures/path-filter-fixture/` contains two source files
// — `Sources/A/x.swift` and `Sources/B/y.swift` — each carrying a
// call-site `__unchecked:` argument that `Lint.Rule.Unchecked` fires
// on. Each test activates `Lint.Rule.Unchecked` with a different
// `paths:` filter shape and asserts the resulting finding count.
//
// Filter prefixes are bare run-root-relative strings (e.g.,
// `"Sources/A"`) — the walker emits relative
// ``Lint/Source/Path`` values per its run-root-stripping contract,
// so prefix matches against bare relative entries align without any
// absolute-root concatenation at call sites. This is the typed-rim,
// typed-throughout shape: tests author intent (`"Sources/A"`), the
// walker handles the mechanism (root-prefix strip).

extension Lint.Run.Test.Integration {
    /// Compute the absolute path to the fixture root:
    /// `<swift-linter>/Tests/Fixtures/path-filter-fixture`.
    ///
    /// Resolves from `#filePath` of the test source so the path is
    /// independent of the working directory at `swift test` time.
    private static func fixtureRoot(testFile: Swift.String = #filePath) throws(Paths.Path.Error) -> File.Path {
        // testFile = .../swift-linter/Tests/Linter Core Tests/Lint.Run Tests.swift
        // Strip the filename and the test-target directory, leaving
        // .../swift-linter/Tests/, then descend into the fixture path.
        var components: [Swift.String] = testFile
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(Swift.String.init)
        _ = components.popLast() // "Lint.Run Tests.swift"
        _ = components.popLast() // "Linter Core Tests"
        components.append("Fixtures")
        components.append("path-filter-fixture")
        return try File.Path(components.joined(separator: "/"))
    }

    @Test
    func `paths .all yields findings for both A and B`() throws(Lint.Run.Error) {
        // `fixtureRoot` validates a path composed from `#filePath`;
        // failure indicates a compile-time invariant break, so `try!`
        // is justified per [API-ERR-001]'s precondition exception.
        let root = try! Self.fixtureRoot()
        let configuration = Lint.Configuration {
            .enable(.`test fixture`, paths: .all)
        }
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 2)
    }

    @Test
    func `paths .including A yields finding for A only`() throws(Lint.Run.Error) {
        let root = try! Self.fixtureRoot()
        let configuration = Lint.Configuration {
            .enable(.`test fixture`, paths: .including(["Sources/A"]))
        }
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 1)
        #expect(findings.first?.record.location.filePath?.hasSuffix("/Sources/A/x.swift") == true)
    }

    @Test
    func `paths .excluding B yields finding for A only`() throws(Lint.Run.Error) {
        let root = try! Self.fixtureRoot()
        let configuration = Lint.Configuration {
            .enable(.`test fixture`, paths: .excluding(["Sources/B"]))
        }
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 1)
        #expect(findings.first?.record.location.filePath?.hasSuffix("/Sources/A/x.swift") == true)
    }

    @Test
    func `paths .including non-matching yields no findings`() throws(Lint.Run.Error) {
        let root = try! Self.fixtureRoot()
        let configuration = Lint.Configuration {
            .enable(.`test fixture`, paths: .including(["Tests/Fixtures/Other"]))
        }
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 0)
    }
}
