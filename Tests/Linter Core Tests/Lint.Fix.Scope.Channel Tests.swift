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

extension Lint.Fix.Scope.Channel {
    @Suite struct Test {}
}

extension Lint.Fix.Scope.Channel.Test {
    @Test
    func `target roots round trip without losing spaces or order`() throws(Lint.Fix.Scope.Channel
        .Error)
    {
        let roots: [File.Path] = [
            File.Path("/package/Sources/Library"),
            File.Path("/package/Tests/Library Tests"),
        ]
        let decoded = try Lint.Fix.Scope.Channel.resolve(
            Lint.Fix.Scope.Channel.value(roots)
        )
        #expect(decoded == roots)
    }

    @Test
    func `malformed set channel fails loud`() {
        do throws(Lint.Fix.Scope.Channel.Error) {
            _ = try Lint.Fix.Scope.Channel.resolve("not-json")
            Issue.record("a malformed target-root channel must throw")
        } catch {
            switch error {
            case .unparseable:
                break

            case .invalid:
                Issue.record("expected .unparseable, got \(error)")
            }
        }
    }
}
