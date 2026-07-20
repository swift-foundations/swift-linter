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

internal import Environment

extension Lint.Rule.Bundle.Baked {
    /// Environment channel carrying the dispatcher's baked-bundle selection to
    /// the prebuilt standard runner.
    ///
    /// The runner bakes EVERY published standard bundle (see
    /// ``Lint/Rule/Bundle/Baked``); which one a given spawn must lint with is
    /// the consumer's choice, recognized by the
    /// ``Lint/File/Single/Classifier`` and exported here by the runner spawn
    /// (``Lint/File/Single/Runner/run(binary:consumerPackageRoot:arguments:selection:bundle:nonce:)``)
    /// before exec. The runner's `Lint.run(bundles:)` reads the channel and
    /// selects the matching baked rule set. An environment channel (not an
    /// argv flag) because the dispatcher forwards the consumer's lint-target
    /// argv VERBATIM — a flag would be indistinguishable from a path argument.
    ///
    /// Unset ⇒ `nil` (caller applies the `primitives` default — the sole
    /// bundle the pre-A4 dispatcher ever routed, so an OLD dispatcher spawning
    /// a NEW runner still lints exactly what it always did). SET-but-
    /// unrecognized fails loud via ``Error/invalid(value:)``: a machine-set
    /// channel carrying an unknown token is version skew between dispatcher
    /// and runner, and linting a SUBSTITUTED bundle would be a
    /// wrong-result-that-exits-0 hazard (mirrors the exit-policy / selection /
    /// parent channel discipline).
    public enum Channel {
        /// The environment variable name.
        public static let variable: Swift.String = "SWIFT_LINTER_BUNDLE"

        /// A set-but-unrecognized channel value.
        public enum Error: Swift.Error, Swift.Equatable {
            case invalid(value: Swift.String)
        }

        /// Read the baked-bundle selection from the process environment.
        ///
        /// - Returns: the parsed token, or `nil` when the variable is unset.
        /// - Throws: ``Error/invalid(value:)`` when set to a value outside the
        ///   ``Lint/Rule/Bundle/Baked`` vocabulary.
        public static func read() throws(Error) -> Lint.Rule.Bundle.Baked? {
            guard let raw: Swift.String = Environment.read(Self.variable) else {
                return nil
            }
            guard let bundle: Lint.Rule.Bundle.Baked = Lint.Rule.Bundle.Baked(rawValue: raw) else {
                throw .invalid(value: raw)
            }
            return bundle
        }
    }
}
