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
import Testing

@testable import Linter_Core

extension Lint.Run.Policy.Channel {
    @Suite(.serialized)
    struct Test {}
}

// MARK: - Lint.Run.Policy.Channel
//
// The exit-policy environment channel mirrors the selection / parent channel
// contract:
//   - read() == nil ONLY when the variable is UNSET (advisory default);
//   - each vocabulary raw value round-trips;
//   - HARD-ERROR (throw) when the variable is SET to a value outside the
//     ``Lint/Run/Policy`` vocabulary — NEVER a silent advisory fall-through
//     that would weaken a requested strict exit into exit-0.
//
// The suite is `.serialized` and restores the process variable after each
// case: the channel reads the REAL process environment (that is what the
// spawned dispatch executables inherit), so tests mutate it via
// `Environment.write` rather than a TaskLocal overlay.

extension Lint.Run.Policy.Channel.Test {
    private func withVariable(_ value: Swift.String?, body: () -> Swift.Void) {
        if let value {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write(Lint.Run.Policy.Channel.variable, to: value)
        } else {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write.unset(Lint.Run.Policy.Channel.variable)
        }
        defer {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write.unset(Lint.Run.Policy.Channel.variable)
        }
        body()
    }

    @Test("unset variable reads nil (advisory default)")
    func unsetReadsNil() {
        withVariable(nil) {
            // swift-format-ignore: NeverUseForceTry
            #expect(try! Lint.Run.Policy.Channel.read() == nil)
        }
    }

    @Test("each policy raw value round-trips")
    func vocabularyRoundTrips() {
        for policy in Lint.Run.Policy.allCases {
            withVariable(policy.rawValue) {
                // swift-format-ignore: NeverUseForceTry
                #expect(try! Lint.Run.Policy.Channel.read() == policy)
            }
        }
    }

    @Test("set-but-unrecognized value fails loud")
    func invalidValueThrows() {
        withVariable("warnings-as-errors") {
            #expect(throws: Lint.Run.Policy.Channel.Error.invalid(value: "warnings-as-errors")) {
                try Lint.Run.Policy.Channel.read()
            }
        }
    }
}
