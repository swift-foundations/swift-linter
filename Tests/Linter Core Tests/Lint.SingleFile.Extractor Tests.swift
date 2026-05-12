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
@testable import Linter_Core

extension Lint.SingleFile.Extractor {
    @Suite
    struct Test {
        @Suite struct PackageName {}
    }
}

// MARK: - packageName(fromPath:consumerPackageRoot:)
//
// SwiftPM rejects the literal `"."` as a package name (`unknown package '.'`);
// the self-reference path forms (`""` and `"."`) must derive the package name
// from the consumer-root directory's basename instead — companion to the
// `resolveConsumerPath` self-reference shortcut on the path-resolution side.

extension Lint.SingleFile.Extractor.Test.PackageName {
    @Test
    func `Sibling-package relative path uses path's own basename`() {
        let name = Lint.SingleFile.Extractor.packageName(
            fromPath: "../swift-primitives-linter-rules",
            consumerPackageRoot: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives"
        )
        #expect(name == "swift-primitives-linter-rules")
    }

    @Test
    func `Absolute path uses path's own basename`() {
        let name = Lint.SingleFile.Extractor.packageName(
            fromPath: "/Users/coen/Developer/swift-foundations/swift-linter-rules",
            consumerPackageRoot: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives"
        )
        #expect(name == "swift-linter-rules")
    }

    @Test
    func `Self-reference dot derives package name from consumer-root basename`() {
        let name = Lint.SingleFile.Extractor.packageName(
            fromPath: ".",
            consumerPackageRoot: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives"
        )
        #expect(name == "swift-cardinal-primitives")
    }

    @Test
    func `Self-reference empty string derives package name from consumer-root basename`() {
        let name = Lint.SingleFile.Extractor.packageName(
            fromPath: "",
            consumerPackageRoot: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives"
        )
        #expect(name == "swift-cardinal-primitives")
    }

    @Test
    func `Self-reference dot strips trailing slash from consumer-root`() {
        let name = Lint.SingleFile.Extractor.packageName(
            fromPath: ".",
            consumerPackageRoot: "/Users/coen/Developer/swift-primitives/swift-cardinal-primitives/"
        )
        #expect(name == "swift-cardinal-primitives")
    }
}
