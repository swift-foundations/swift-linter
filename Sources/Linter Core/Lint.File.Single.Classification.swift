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

extension Lint.File.Single {
    /// Routing verdict for a Shape-γ consumer: whether the prebuilt
    /// "standard runner" can lint it warm (the Phase-3 fast path) or it
    /// must take the eval-materialize-compile fallback.
    ///
    /// Produced by ``Classifier/classify(source:dependencies:)`` and
    /// consumed by ``dispatch(at:arguments:)``. The fast path is only
    /// taken when a prebuilt runner is provisioned (the
    /// `SWIFT_LINTER_RUNNER` environment variable); otherwise dispatch
    /// always takes the eval path regardless of this verdict, so the
    /// classification is purely additive.
    ///
    /// Phase 3 of
    /// `Research/near-instant-lint-with-external-rule-loading.md`.
    public enum Classification: Swift.Sendable, Swift.Equatable {
        /// The consumer activates exactly the standard
        /// `Lint.Rule.Bundle.primitives` with no per-consumer
        /// selection, no inline/custom rules, no parent chain, and only
        /// standard rule-pack dependencies. Its active rule set is
        /// byte-for-byte the set the standard runner bakes, so the
        /// runner reproduces the eval result without recompiling.
        case fastPathStandardBundle

        /// The consumer activates exactly
        /// `Lint.Rule.Bundle.primitives.excluding(rules: [...])` — the
        /// standard bundle minus a set of per-package exclusions — with no
        /// other selection, no inline rules, and no parent chain. Every
        /// excluded rule ID was extracted exactly (string-literal or
        /// `.id`-accessor form); if any element could not be read with
        /// certainty the consumer is classified `.evalFallback` instead, so a
        /// dropped exclusion never silently fires a rule. The runner reproduces
        /// the result by linting the baked `Bundle.primitives` registry with
        /// `disabled` overlaid via ``Lint/Configuration/lift(manifest:registry:inheriting:)``.
        case fastPathStandardBundleExcluding(disabled: Swift.Set<Lint.Rule.ID>)

        /// The runner cannot faithfully reproduce this consumer's
        /// result — inline/custom rules, non-standard packs, a
        /// non-`primitives` bundle, per-consumer enable/disable/exclude,
        /// a `// parent:` inheritance chain, or an unparseable manifest.
        /// Routes to the eval fallback. `reason` names the disqualifier
        /// for diagnostics.
        case evalFallback(reason: Swift.String)
    }
}
