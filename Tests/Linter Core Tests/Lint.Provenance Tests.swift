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
import Testing

@testable import Linter_Core

extension Lint.Provenance {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct Integration {}
        @Suite struct `Edge Case` {}
    }
}

// The engine-layer integration tests use a synthetic rule that fires once
// per visited source file — sufficient signal to prove which files the
// provenance exemption removed from the run's INPUT, independent of any
// rule pack.
extension Lint.Rule {
    fileprivate static let `provenance fixture` = Lint.Rule(
        id: "provenance fixture",
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
                    identifier: "provenance fixture",
                    message: "provenance fixture rule fired"
                )
            ]
        }
    )
}

extension Lint.Provenance.Test {
    /// Computes `<swift-linter>/Tests/Fixtures/<name>` from `#filePath`.
    fileprivate static func fixtureRoot(
        _ name: Swift.String,
        testFile: Swift.String = #filePath
    ) throws(Paths.Path.Error) -> File.Path {
        var components: [Swift.String] =
            testFile
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(Swift.String.init)
        _ = components.popLast()  // "Lint.Provenance Tests.swift"
        _ = components.popLast()  // "Linter Core Tests"
        components.append("Fixtures")
        components.append(name)
        return try File.Path(components.joined(separator: "/"))
    }
}

extension Lint.Provenance.Test.Unit {
    @Test
    func `register declares the certificate-verification fork with its upstream coordinates`() {
        let entry = Lint.Provenance.Register.declared.first {
            $0.package == "swift-certificate-verification"
        }
        #expect(entry?.upstream.repository == "apple/swift-certificates")
        #expect(entry?.upstream.commit == "24ccdeeeed4dfaae7955fcac9dbf5489ed4f1a25")
        #expect(entry?.vendored.isEmpty == false)
    }

    @Test
    func `directory scope matches whole segments only`() {
        let scope = Lint.Provenance.Scope.directory("Sources/X509")
        #expect(scope.matches(Lint.Source.Path("Sources/X509/Certificate.swift")))
        #expect(scope.matches(Lint.Source.Path("Sources/X509/Nested/Deep.swift")))
        // Segment near-miss: a sibling whose name merely shares the textual
        // prefix must NOT be admitted.
        #expect(!scope.matches(Lint.Source.Path("Sources/X509Extra/Certificate.swift")))
        // A file NAMED like the directory is not inside it.
        #expect(!scope.matches(Lint.Source.Path("Sources/X509")))
        // Positive control for the class: a bare filename with no directory
        // component is never admitted by any directory entry.
        #expect(!scope.matches(Lint.Source.Path("X509.swift")))
        #expect(!scope.matches(Lint.Source.Path("")))
    }

    @Test
    func `file scope matches the exact path only`() {
        let scope = Lint.Provenance.Scope.file("Tests/X509Tests/CommonName.swift")
        #expect(scope.matches(Lint.Source.Path("Tests/X509Tests/CommonName.swift")))
        #expect(!scope.matches(Lint.Source.Path("Tests/X509Tests/CommonName.swift.bak")))
        #expect(!scope.matches(Lint.Source.Path("Tests/X509Tests/Nested/CommonName.swift")))
        #expect(!scope.matches(Lint.Source.Path("CommonName.swift")))
    }

    @Test
    func `manifest identity reads the Package initializer name and not a product name`() {
        let manifest = """
            // swift-tools-version: 6.3.3
            import PackageDescription

            let package = Package(
                name: "swift-certificate-verification",
                products: [
                    .library(name: "Certificates", targets: ["Certificates"])
                ]
            )
            """
        #expect(Lint.Provenance.package(inManifest: manifest) == "swift-certificate-verification")
    }

    @Test
    func `manifest without a Package initializer yields no identity`() {
        #expect(Lint.Provenance.package(inManifest: "let x = 1") == nil)
    }
}

extension Lint.Provenance.Test.Integration {
    @Test
    func `declared fork run exempts vendored scope and lints everything else`() throws(Lint.Run.Error) {
        // Fixture population (6 walked files):
        //   Package.swift                      → linted (fires)
        //   Sources/X509/Vendored.swift        → EXEMPT (scope + attribution)
        //   Sources/X509/Unattributed.swift    → linted (near-miss: no attribution)
        //   Tests/X509Tests/CommonName.swift   → EXEMPT (file scope + attribution)
        //   Tests/X509Tests/TestPKI.swift      → linted (near-miss: not enumerated)
        //   Vendored.swift (bare filename)     → linted (positive control)
        let root = try! Lint.Provenance.Test.fixtureRoot("provenance-fork-fixture")
        let configuration = Lint.Configuration {
            .enable(.`provenance fixture`)
        }
        let outcome = try Lint.Run.run(paths: [root], capturing: .all, configuration: configuration)
        #expect(outcome.findings.count == 4)
        #expect(outcome.filesLinted == 4)
        #expect(outcome.filesExempted == 2)
        let fired: [Swift.String] = outcome.findings.compactMap(\.record.location.filePath)
        #expect(!fired.contains { $0.hasSuffix("/Sources/X509/Vendored.swift") })
        #expect(!fired.contains { $0.hasSuffix("/Tests/X509Tests/CommonName.swift") })
        #expect(fired.contains { $0.hasSuffix("/Sources/X509/Unattributed.swift") })
        #expect(fired.contains { $0.hasSuffix("/Tests/X509Tests/TestPKI.swift") })
    }

    @Test
    func `undeclared package falsely claiming heritage is fully linted`() throws(Lint.Run.Error) {
        // The path and header mimic the declared fork, but the package name
        // is not in the central register — identity resolution fails and
        // every file is linted (2 walked files: Package.swift + the claimer).
        let root = try! Lint.Provenance.Test.fixtureRoot("provenance-nonfork-fixture")
        let configuration = Lint.Configuration {
            .enable(.`provenance fixture`)
        }
        let outcome = try Lint.Run.run(paths: [root], capturing: .all, configuration: configuration)
        #expect(outcome.findings.count == 2)
        #expect(outcome.filesExempted == 0)
    }
}

extension Lint.Provenance.Test.`Edge Case` {
    @Test
    func `root without a manifest resolves no fork`() {
        let root = try! Lint.Provenance.Test.fixtureRoot("path-filter-fixture")
        #expect(Lint.Provenance.resolve(root: root) == nil)
    }
}
