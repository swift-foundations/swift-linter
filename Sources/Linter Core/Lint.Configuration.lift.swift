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

internal import Linter_Primitives

extension Lint.Configuration {
    /// Lift a wire-format ``Lint/Manifest`` into a runtime
    /// ``Lint/Configuration`` using a local rule registry.
    ///
    /// `manifest` is typically a parent manifest fetched over the
    /// network (per the `// parent: <URL>` directive) — its rule
    /// references are string IDs that cannot reach Swift witness
    /// values across the JSON wire-format boundary.
    ///
    /// `registry` is the consumer's local lookup table from rule ID
    /// to the runtime ``Lint/Rule`` witness value. Built by the
    /// consumer's eval-project executable from its collected
    /// `[Lint.Rule.Configuration]` entries: each entry's `rule.id` →
    /// `rule`. Only rules the consumer has declared (via its own
    /// imports and rule activations) are eligible for lifting.
    ///
    /// Unmatched parent IDs (parent enables a rule the consumer
    /// hasn't registered) are **silently dropped**. The caller can
    /// emit a warning if visibility into dropped IDs is needed —
    /// the lift itself returns only entries it could resolve.
    ///
    /// `disabledRuleIDs` and `excludedPaths` flow through verbatim:
    /// rule-wide disables apply regardless of which layer registered
    /// the rule (per `Lint.Configuration.rules.effective`);
    /// excluded-path filters compose at the walker.
    public static func lift(
        manifest: Lint.Manifest,
        registry: [Lint.Rule.ID: Lint.Rule],
        inheriting parent: Lint.Configuration? = nil
    ) -> Lint.Configuration {
        var entries: [Lint.Rule.Configuration] = []
        for id in manifest.rules.enabled {
            if let rule: Lint.Rule = registry[id] {
                entries.append(Lint.Rule.Configuration.enable(rule))
            }
        }
        let exclusions: [Lint.Filter.Prefix] = manifest.excluded.map(Lint.Filter.Prefix.init)
        return Lint.Configuration(
            inheriting: parent,
            excluded: exclusions,
            disabled: manifest.rules.disabled
        ) {
            entries
        }
    }
}
