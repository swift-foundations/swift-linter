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

extension Lint.Rule.Bundle.Baked.Channel {
    @Suite(.serialized)
    struct Test {}
}

// MARK: - Lint.Rule.Bundle.Baked.Channel
//
// The baked-bundle environment channel mirrors the exit-policy channel
// contract:
//   - read() == nil ONLY when the variable is UNSET (the caller applies the
//     `primitives` default — the sole bundle a pre-A4 dispatcher routed);
//   - each vocabulary raw value round-trips;
//   - HARD-ERROR (throw) when the variable is SET to a value outside the
//     ``Lint/Rule/Bundle/Baked`` vocabulary — NEVER a silent substitution
//     of a different bundle than the consumer selected.
//
// The suite is `.serialized` and restores the process variable after each
// case: the channel reads the REAL process environment (that is what the
// spawned standard runner inherits), so tests mutate it via
// `Environment.write` rather than a TaskLocal overlay.

extension Lint.Rule.Bundle.Baked.Channel.Test {
    private func withVariable(_ value: Swift.String?, body: () -> Swift.Void) {
        if let value {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write(Lint.Rule.Bundle.Baked.Channel.variable, to: value)
        } else {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write.unset(Lint.Rule.Bundle.Baked.Channel.variable)
        }
        defer {
            // swift-format-ignore: NeverUseForceTry
            try! Environment.write.unset(Lint.Rule.Bundle.Baked.Channel.variable)
        }
        body()
    }

    @Test("unset variable reads nil (primitives default applied by the caller)")
    func unsetReadsNil() {
        withVariable(nil) {
            // swift-format-ignore: NeverUseForceTry
            #expect(try! Lint.Rule.Bundle.Baked.Channel.read() == nil)
        }
    }

    @Test("each baked-bundle raw value round-trips")
    func vocabularyRoundTrips() {
        for bundle in Lint.Rule.Bundle.Baked.allCases {
            withVariable(bundle.rawValue) {
                // swift-format-ignore: NeverUseForceTry
                #expect(try! Lint.Rule.Bundle.Baked.Channel.read() == bundle)
            }
        }
    }

    @Test("set-but-unrecognized value fails loud")
    func invalidValueThrows() {
        withVariable("universal") {
            #expect(throws: Lint.Rule.Bundle.Baked.Channel.Error.invalid(value: "universal")) {
                try Lint.Rule.Bundle.Baked.Channel.read()
            }
        }
    }

    @Test("each token's expression is the consumer-side bundle accessor")
    func expressionsMatchAccessors() {
        #expect(Lint.Rule.Bundle.Baked.primitives.expression == "Lint.Rule.Bundle.primitives")
        #expect(Lint.Rule.Bundle.Baked.standards.expression == "Lint.Rule.Bundle.standards")
        #expect(Lint.Rule.Bundle.Baked.institute.expression == "Lint.Rule.Bundle.institute")
    }
}
