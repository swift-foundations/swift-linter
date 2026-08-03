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

extension Lint.Fix.Scope.Manifest.Channel {
    @Suite struct Test {}
}

extension Lint.Fix.Scope.Manifest.Channel.Test {
    @Test
    func `a manifest path round trips without losing spaces`() throws(Lint.Fix.Scope.Manifest.Channel.Error) {
        let path = File.Path("/package with spaces/Package.swift")
        let decoded = try Lint.Fix.Scope.Manifest.Channel.resolve(
            Lint.Fix.Scope.Manifest.Channel.value(path)
        )
        #expect(decoded == path)
    }

    @Test
    func `malformed manifest channel fails loud`() {
        do throws(Lint.Fix.Scope.Manifest.Channel.Error) {
            _ = try Lint.Fix.Scope.Manifest.Channel.resolve("not-json")
            Issue.record("a malformed manifest channel must throw")
        } catch {
            switch error {
            case .unparseable:
                break

            case .invalid:
                Issue.record("expected .unparseable, got \(error)")
            }
        }
    }

    @Test
    func `a non-string JSON manifest channel value is rejected`() {
        do throws(Lint.Fix.Scope.Manifest.Channel.Error) {
            _ = try Lint.Fix.Scope.Manifest.Channel.resolve("[\"not-a-string\"]")
            Issue.record("a JSON array must not be accepted as the manifest channel's single path")
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
