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
import Linter_Primitives
import Linter_Rule_Unchecked
@testable import Linter_Core

extension Lint.Run {
    @Suite
    struct Test {
        @Suite struct Integration {}
    }
}

// MARK: - Path filter integration
//
// Engine-layer integration coverage for the per-rule
// `Lint.Rule.Configuration.paths` filter (`Path.Filter`). The fixture
// at `Tests/Fixtures/path-filter-fixture/` contains two source files
// — `Sources/A/x.swift` and `Sources/B/y.swift` — each carrying a
// call-site `__unchecked:` argument that `Lint.Rule.Unchecked` fires
// on. Each test activates `Lint.Rule.Unchecked` with a different
// `paths:` filter shape and asserts the resulting finding count.
//
// Filter prefixes are computed as absolute paths anchored on the
// fixture root (derived from `#filePath`). The walker
// (`Lint.Source.Walker.swiftSourcePaths(under:)`) emits absolute
// source paths when the run root is absolute, so the prefix entries
// must align with that emitted form per `Path.Filter`'s documented
// contract — typed at construction (`Path.Filter.Prefix`), bare at
// the L3 walker boundary.

extension Lint.Run.Test.Integration {
    /// Compute the absolute path to the fixture root:
    /// `<swift-linter>/Tests/Fixtures/path-filter-fixture`.
    ///
    /// Resolves from `#filePath` of the test source so the path is
    /// independent of the working directory at `swift test` time.
    private static func fixtureRoot(testFile: Swift.String = #filePath) -> Swift.String {
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
        return components.joined(separator: "/")
    }

    @Test
    func `paths .all yields findings for both A and B`() throws {
        let root = Self.fixtureRoot()
        let configuration = Lint.Configuration(rules: {
            .enable(Lint.Rule.Unchecked.self, paths: .all)
        })
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 2)
    }

    @Test
    func `paths .including A yields finding for A only`() throws {
        let root = Self.fixtureRoot()
        let aPrefix: Linter_Primitives.Path.Filter.Prefix = .init(root + "/Sources/A")
        let configuration = Lint.Configuration(rules: {
            .enable(Lint.Rule.Unchecked.self, paths: .including([aPrefix]))
        })
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 1)
        #expect(findings.first?.location.filePath?.hasSuffix("/Sources/A/x.swift") == true)
    }

    @Test
    func `paths .excluding B yields finding for A only`() throws {
        let root = Self.fixtureRoot()
        let bPrefix: Linter_Primitives.Path.Filter.Prefix = .init(root + "/Sources/B")
        let configuration = Lint.Configuration(rules: {
            .enable(Lint.Rule.Unchecked.self, paths: .excluding([bPrefix]))
        })
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 1)
        #expect(findings.first?.location.filePath?.hasSuffix("/Sources/A/x.swift") == true)
    }

    @Test
    func `paths .including non-matching yields no findings`() throws {
        let root = Self.fixtureRoot()
        let nonMatch: Linter_Primitives.Path.Filter.Prefix = .init(root + "/Tests/Fixtures/Other")
        let configuration = Lint.Configuration(rules: {
            .enable(Lint.Rule.Unchecked.self, paths: .including([nonMatch]))
        })
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        #expect(findings.count == 0)
    }
}
