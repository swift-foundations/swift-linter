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

public import Linter_Primitives

extension Lint.Rule.Bundle {
    /// The vocabulary of published standard bundles the prebuilt "standard
    /// runner" bakes (the A4-gap closure over the original
    /// primitives-only fast path).
    ///
    /// One token per baked bundle: the ``Lint/File/Single/Classifier``
    /// recognizes the token's consumer-side ``expression`` and threads the
    /// token through ``Lint/File/Single/Classification`` to the runner spawn,
    /// which exports it on the ``Channel`` so the runner's
    /// `Lint.run(bundles:)` selects the matching baked rule set. The
    /// vocabulary is the single source of truth for both sides — adding a
    /// baked bundle is one new case here plus its bake in the runner's
    /// `main.swift` and `Runner/Package.swift`.
    ///
    /// Philosophy guard: a token NEVER substitutes a different rule set than
    /// the consumer selected. The classifier emits a token only when the
    /// consumer's active rule set is provably exactly that bundle (or the
    /// bundle minus exactly-extracted exclusions); the runner fails loud on a
    /// token it does not bake. `universal` is deliberately absent — its sole
    /// consumer is the universal pack's own self-lint, which takes the eval
    /// fallback.
    ///
    /// Raw values ARE the channel wire vocabulary (see ``Channel``) AND the
    /// trailing member name of the consumer-side bundle accessor, so the enum
    /// stays in lock-step with the published packs by construction.
    public enum Baked: Swift.String, Swift.CaseIterable, Swift.Sendable {
        /// `Lint.Rule.Bundle.primitives` — published by
        /// `swift-primitives-linter-rules`.
        case primitives

        /// `Lint.Rule.Bundle.standards` — published by
        /// `swift-standards-linter-rules`.
        case standards

        /// `Lint.Rule.Bundle.institute` — published by
        /// `swift-institute-linter-rules`.
        case institute
    }
}

extension Lint.Rule.Bundle.Baked {
    /// The exact consumer-side member-access expression that activates
    /// this bundle in a `Lint.swift` rule closure.
    ///
    /// The classifier matches a candidate expression's
    /// `trimmedDescription` against this string — byte-for-byte, no
    /// normalization — so a match guarantees the consumer wrote precisely
    /// this bundle accessor.
    public var expression: Swift.String {
        "Lint.Rule.Bundle.\(self.rawValue)"
    }
}
