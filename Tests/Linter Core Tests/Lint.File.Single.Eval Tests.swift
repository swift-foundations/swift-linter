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

import Environment
import File_System
import Linter
import Testing

@testable import Linter_Core

extension Lint.File.Single.Test {
    @Suite
    struct Eval {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

// MARK: - environment(inheriting:parent:)
//
// The eval dispatcher may add a parent-manifest channel, but it must preserve
// the coordinator's complete snapshot either way. In particular, SARIF must
// reach the compiled `Lint.run(configuration:)` terminal unchanged.

extension Lint.File.Single.Test.Eval.Unit {
    @Test
    func `SARIF selection survives eval without a parent manifest`() {
        let environment = Lint.File.Single.Eval.environment(
            inheriting: Environment.Snapshot([
                Lint.Reporter.Format.Channel.variable:
                    Lint.Reporter.Format.Channel.value(.sarif)
            ]),
            parent: nil
        )
        #expect(
            environment[Lint.Reporter.Format.Channel.variable]
                == Lint.Reporter.Format.Channel.value(.sarif)
        )
    }

    @Test
    func `Parent overlay preserves SARIF and adds only its channel`() {
        let parent = File.Path("/tmp/swift-linter-parent.json")
        let environment = Lint.File.Single.Eval.environment(
            inheriting: Environment.Snapshot([
                Lint.Reporter.Format.Channel.variable:
                    Lint.Reporter.Format.Channel.value(.sarif)
            ]),
            parent: parent
        )
        #expect(
            environment[Lint.Reporter.Format.Channel.variable]
                == Lint.Reporter.Format.Channel.value(.sarif)
        )
        #expect(environment[Lint.File.Single.Channel.parent.variable] == parent.string)
    }
}
