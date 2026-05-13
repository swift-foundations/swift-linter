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

extension Lint.SingleFile.Materializer {
    @Suite
    struct Test {
        @Suite struct Resolve {}
    }
}

// MARK: - resolve(_:relativeTo:)
//
// The eval project's Package.swift sits at `<consumerRoot>/.swift-lint/eval/`,
// two directory levels below the consumer root. `resolve(_:relativeTo:)` rewrites
// the consumer-declared `.package(path: X)` value into a path relative to the
// eval Package.swift's location.
//
// `"."` and `""` are self-reference shortcuts — both name the consumer's own
// package. Naive concatenation produces `"../../."` / `"../../"`, the first
// of which SwiftPM rejects as "unknown package '.'".

extension Lint.SingleFile.Materializer.Test.Resolve {
    @Test
    func `Sibling-package path is prefixed with the eval-to-consumer hop`() throws(Lint.SingleFile.Error) {
        let resolved = try Lint.SingleFile.Materializer.resolve(
            "../../swift-primitives-linter-rules",
            relativeTo: "../.."
        )
        #expect(resolved == "../../../../swift-primitives-linter-rules")
    }

    @Test
    func `Absolute path is returned unchanged`() throws(Lint.SingleFile.Error) {
        let resolved = try Lint.SingleFile.Materializer.resolve(
            "/Users/coen/Developer/swift-linter-rules",
            relativeTo: "../.."
        )
        #expect(resolved == "/Users/coen/Developer/swift-linter-rules")
    }

    @Test
    func `Self-reference dot collapses to root without trailing slash-dot`() throws(Lint.SingleFile.Error) {
        // SwiftPM rejects `.package(path: "../../.")` with "unknown package '.'";
        // the self-reference shortcut returns the bare `root` instead.
        let resolved = try Lint.SingleFile.Materializer.resolve(
            ".",
            relativeTo: "../.."
        )
        #expect(resolved == "../..")
    }

    @Test
    func `Self-reference empty string collapses to root without trailing slash`() throws(Lint.SingleFile.Error) {
        let resolved = try Lint.SingleFile.Materializer.resolve(
            "",
            relativeTo: "../.."
        )
        #expect(resolved == "../..")
    }
}
