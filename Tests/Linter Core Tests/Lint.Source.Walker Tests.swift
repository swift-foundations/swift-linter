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

extension Lint.Source.Walker {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct Integration {}
    }
}

// Engine-level walker tests use a synthetic fixture rule constructed
// inline; the engine package has no dependency on any rule pack.
// `fileprivate` keeps this declaration scoped to this test file (the
// sibling `Lint.Run Tests.swift` carries its own `fileprivate` rule
// for its own assertions; the two declarations do not collide).
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

// MARK: - Nested-package skip
//
// A consumer's source tree MAY contain ad-hoc experimental SwiftPM
// packages under `Experiments/<name>/` (each with its own
// `Package.swift`). The outer consumer's lint run MUST NOT descend
// into those nested package subtrees — they are independent packages
// owned by their own manifests and get linted independently when the
// linter is invoked on their roots.
//
// The fixture at `Tests/Fixtures/nested-package-fixture/` carries:
//
// ```
// Package.swift                                     <- outer consumer manifest
// Sources/Outer/x.swift                             <- outer source
// Experiments/inner/Package.swift                   <- nested manifest
// Experiments/inner/Sources/Inner/y.swift           <- nested source
// ```
//
// The walker MUST emit only `Package.swift` and `Sources/Outer/x.swift`.

extension Lint.Source.Walker.Test {
    /// Compute the absolute path to the fixture root:
    /// `<swift-linter>/Tests/Fixtures/nested-package-fixture`.
    fileprivate static func fixtureRoot(testFile: Swift.String = #filePath) throws(Paths.Path.Error) -> File.Path {
        var components: [Swift.String] = testFile
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(Swift.String.init)
        _ = components.popLast() // "Lint.Source.Walker Tests.swift"
        _ = components.popLast() // "Linter Core Tests"
        components.append("Fixtures")
        components.append("nested-package-fixture")
        return try File.Path(components.joined(separator: "/"))
    }
}

extension Lint.Source.Walker.Test.Unit {
    @Test
    func `paths(under:) emits outer manifest and source but skips nested-package subtree`() {
        // `fixtureRoot` validates a path composed from `#filePath`;
        // failure indicates a compile-time invariant break, so `try!`
        // is justified per [API-ERR-001]'s precondition exception.
        let root = try! Lint.Source.Walker.Test.fixtureRoot()
        let paths = Lint.Source.Walker.paths(under: root).map(\.underlying)
        #expect(paths == [
            "Package.swift",
            "Sources/Outer/x.swift",
        ])
    }
}

extension Lint.Source.Walker.Test.Integration {
    @Test
    func `Lint.Run.run does not visit files inside a nested-package subtree`() throws(Lint.Run.Error) {
        let root = try! Lint.Source.Walker.Test.fixtureRoot()
        let configuration = Lint.Configuration {
            .enable(.`test fixture`, paths: .all)
        }
        let findings = try Lint.Run.run(paths: [root], configuration: configuration)
        // 2 outer files (Package.swift + Sources/Outer/x.swift); 0 from
        // the nested `Experiments/inner/` subtree. Without the skip,
        // this would be 4.
        #expect(findings.count == 2)
        let paths = Set(findings.compactMap(\.record.location.filePath))
        #expect(paths.contains(where: { $0.hasSuffix("/nested-package-fixture/Package.swift") }))
        #expect(paths.contains(where: { $0.hasSuffix("/Sources/Outer/x.swift") }))
        #expect(paths.allSatisfy { !$0.contains("/Experiments/inner/") })
    }
}
