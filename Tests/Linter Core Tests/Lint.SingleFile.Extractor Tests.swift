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
import Testing
@testable import Linter_Core

extension Lint.SingleFile.Extractor {
    @Suite
    struct Test {
        @Suite struct PackageName {}
    }
}

extension Lint.SingleFile {
    @Suite
    struct Test {
        @Suite struct Canonicalize {}
    }
}

// MARK: - canonicalize(consumerRoot:currentWorkingDirectory:)
//
// CLI-boundary helper that resolves `"."` / empty consumer-root paths
// to the absolute current working directory before any engine-side path
// arithmetic. SwiftPM rejects the literal `"."` as a package name in
// the materialized eval project (`unknown package '.'`); the helper
// closes that gap at the user-input boundary. Closure-injected cwd
// keeps Linter Core kernel-free; the CLI binds the closure to
// Kernel.Directory.Working.withCurrentBytes per the platform skill.

extension Lint.SingleFile.Test.Canonicalize {
    @Test
    func `Dot consumerRoot resolves via cwd closure`() {
        let resolved = Lint.SingleFile.canonicalize(
            consumerRoot: ".",
            currentWorkingDirectory: { "/Users/coen/Developer/swift-cardinal-primitives" }
        )
        #expect(resolved == "/Users/coen/Developer/swift-cardinal-primitives")
    }

    @Test
    func `Empty consumerRoot resolves via cwd closure`() {
        let resolved = Lint.SingleFile.canonicalize(
            consumerRoot: "",
            currentWorkingDirectory: { "/Users/coen/Developer/swift-cardinal-primitives" }
        )
        #expect(resolved == "/Users/coen/Developer/swift-cardinal-primitives")
    }

    @Test
    func `Absolute path is returned unchanged`() {
        let resolved = Lint.SingleFile.canonicalize(
            consumerRoot: "/Users/coen/Developer/swift-cardinal-primitives",
            currentWorkingDirectory: { "/Users/elsewhere" }
        )
        #expect(resolved == "/Users/coen/Developer/swift-cardinal-primitives")
    }

    @Test
    func `Relative non-self path is returned unchanged`() {
        let resolved = Lint.SingleFile.canonicalize(
            consumerRoot: "./Sources",
            currentWorkingDirectory: { "/Users/elsewhere" }
        )
        #expect(resolved == "./Sources")
    }

    @Test
    func `Dot consumerRoot with cwd unavailable falls back to dot`() {
        // When the cwd closure returns nil (e.g., getcwd syscall failure),
        // the canonicalize helper falls back to the input. Downstream
        // SwiftPM resolution will then surface the historic
        // `unknown package '.'` error — failure is loud rather than
        // silently coercing to a bogus path.
        let resolved = Lint.SingleFile.canonicalize(
            consumerRoot: ".",
            currentWorkingDirectory: { nil }
        )
        #expect(resolved == ".")
    }
}

// MARK: - packageName(at:consumerPackageRoot:)
//
// SwiftPM rejects the literal `"."` as a package name (`unknown package '.'`);
// the self-reference path forms (`""` and `"."`) must derive the package name
// from the consumer-root directory's basename instead — companion to the
// `resolve(_:relativeTo:)` self-reference shortcut on the path-resolution side.

extension Lint.SingleFile.Extractor.Test.PackageName {
    @Test
    func `Sibling-package relative path uses path's own basename`() {
        let name = Lint.SingleFile.Extractor.packageName(
            at: "../swift-primitives-linter-rules",
            consumerPackageRoot: File.Path(stringLiteral: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives")
        )
        #expect(name == "swift-primitives-linter-rules")
    }

    @Test
    func `Absolute path uses path's own basename`() {
        let name = Lint.SingleFile.Extractor.packageName(
            at: "/Users/coen/Developer/swift-foundations/swift-linter-rules",
            consumerPackageRoot: File.Path(stringLiteral: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives")
        )
        #expect(name == "swift-linter-rules")
    }

    @Test
    func `Self-reference dot derives package name from consumer-root basename`() {
        let name = Lint.SingleFile.Extractor.packageName(
            at: ".",
            consumerPackageRoot: File.Path(stringLiteral: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives")
        )
        #expect(name == "swift-cardinal-primitives")
    }

    @Test
    func `Self-reference empty string derives package name from consumer-root basename`() {
        let name = Lint.SingleFile.Extractor.packageName(
            at: "",
            consumerPackageRoot: File.Path(stringLiteral: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives")
        )
        #expect(name == "swift-cardinal-primitives")
    }

    @Test
    func `Self-reference dot strips trailing slash from consumer-root`() {
        let name = Lint.SingleFile.Extractor.packageName(
            at: ".",
            consumerPackageRoot: File.Path(stringLiteral: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives/")
        )
        #expect(name == "swift-cardinal-primitives")
    }
}
