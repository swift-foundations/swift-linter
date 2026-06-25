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

import Linter_Primitives
import Testing
@testable import Linter_Core

extension Lint.File.Single.Classifier {
    @Suite
    struct Test {}
}

// MARK: - classify(source:)
//
// Phase-3 fast-path/eval-fallback classifier. A consumer is routed to the
// prebuilt standard runner ONLY when its active rule set is exactly the bare
// `Lint.Rule.Bundle.primitives` the runner bakes — guaranteeing the runner
// reproduces the eval result. Every other shape, and any parse the classifier
// is unsure about, falls back to the eval path (failure-safe). Fixtures mirror
// real ecosystem consumers: swift-array-primitives (bare), swift-cardinal-
// primitives (excludes), swift-carrier-primitives (inline rule + excludes).

extension Lint.File.Single.Classifier.Test {
    /// Pattern helper — `Classification.evalFallback` carries a varying
    /// `reason`, so equality is checked structurally, not by reason text.
    private func isEvalFallback(_ classification: Lint.File.Single.Classification) -> Swift.Bool {
        if case .evalFallback = classification { return true }
        return false
    }

    /// Pattern helper — extract the excluded ID set, or `nil` if the
    /// classification is not `.fastPathStandardBundleExcluding`.
    private func excluded(
        _ classification: Lint.File.Single.Classification
    ) -> Swift.Set<Lint.Rule.ID>? {
        if case .fastPathStandardBundleExcluding(let disabled) = classification { return disabled }
        return nil
    }

    @Test
    func `Bare primitives bundle in a trailing closure is the fast path`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives
            }
            """
        #expect(Lint.File.Single.Classifier.classify(source: source) == .fastPathStandardBundle)
    }

    @Test
    func `Bare primitives bundle in a rules-labelled closure is the fast path`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ], rules: {
                Lint.Rule.Bundle.primitives
            })
            """
        #expect(Lint.File.Single.Classifier.classify(source: source) == .fastPathStandardBundle)
    }

    @Test
    func `Excluding with string-literal IDs is fast path with exact exclusions`() {
        // swift-ordinal-primitives shape: bundle minus per-package excludes,
        // expressed as bare `Lint.Rule.ID` string literals.
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [
                    "raw value access",
                    "chained rawvalue access",
                    "int public parameter",
                    "pointer advanced by",
                ])
            }
            """
        let expected: Swift.Set<Lint.Rule.ID> = [
            "raw value access", "chained rawvalue access", "int public parameter", "pointer advanced by",
        ]
        #expect(excluded(Lint.File.Single.Classifier.classify(source: source)) == expected)
    }

    @Test
    func `Excluding with .id-accessor IDs is fast path with exact exclusions`() {
        // swift-cardinal-primitives shape: typed `Lint.Rule.`name`.id` accessors.
        // The backtick name == the rule's `id:` string (institute convention).
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules
            import Primitives_Linter_Rule_RawValue

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [
                    Lint.Rule.`raw value access`.id,
                    Lint.Rule.`chained rawvalue access`.id,
                    Lint.Rule.`unchecked call site`.id,
                ])
            }
            """
        let expected: Swift.Set<Lint.Rule.ID> = [
            "raw value access", "chained rawvalue access", "unchecked call site",
        ]
        #expect(excluded(Lint.File.Single.Classifier.classify(source: source)) == expected)
    }

    @Test
    func `Excluding with mixed string and .id forms extracts both exactly`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [
                    "raw value access",
                    Lint.Rule.`pointer advanced by`.id,
                ])
            }
            """
        let expected: Swift.Set<Lint.Rule.ID> = ["raw value access", "pointer advanced by"]
        #expect(excluded(Lint.File.Single.Classifier.classify(source: source)) == expected)
    }

    @Test
    func `Excluding with an unreadable element falls back to eval (never guess)`() {
        // A computed/interpolated element the classifier cannot read exactly
        // must drop the WHOLE consumer to the eval fallback — a partially-
        // extracted exclusion set would silently fire an excluded rule.
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [
                    "raw value access",
                    someComputedRuleID(),
                ])
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Excluding with an empty list falls back to eval`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [])
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Inline custom rule plus enable falls back to eval`() {
        // swift-carrier-primitives shape (the 1/78 inline-rule consumer).
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules
            import SwiftSyntax

            extension Lint.Rule {
                static let `sli public carrier import` = Lint.Rule(
                    id: "sli public carrier import",
                    default: .warning,
                    findings: { source, severity in [] }
                )
            }

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives.excluding(rules: [Lint.Rule.`int public parameter`.id])
                Lint.Rule.Configuration.enable(.`sli public carrier import`)
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Non-primitives bundle falls back to eval`() {
        // A bare `institute` bundle is a different rule set than the runner
        // bakes — the primitives runner would over-report (primitives ⊇
        // institute), so it must take the eval fallback.
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Institute_Rules

            Lint.run(dependencies: [
                .package(path: "../../swift-foundations/swift-institute-linter-rules", products: ["Linter Institute Rules"])
            ]) {
                Lint.Rule.Bundle.institute
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Parent inheritance directive falls back to eval`() {
        // The runner's `Lint.run(bundle:)` folds no parent manifest, so a
        // `// parent:` chain could add/remove rules the runner can't reflect.
        let source = """
            // swift-linter-tools-version: 0.1
            // parent: https://github.com/swift-primitives/swift-primitives-linter-rules.git
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `A non-directive parent substring stays on the fast path`() {
        // 2e: the parent gate uses `Manifest.Parent.scan` (line-anchored,
        // leading-30-lines) — the SAME routine the resolver uses — not a raw
        // `source.contains("// parent:")`. A `// parent:` appearing as a
        // trailing comment (not a line-anchored directive) is NOT a parent
        // chain: the resolver would not act on it, so the consumer stays on the
        // fast path. The old substring match wrongly forced eval here.
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives  // not a // parent: directive, just prose
            }
            """
        #expect(Lint.File.Single.Classifier.classify(source: source) == .fastPathStandardBundle)
    }

    @Test
    func `Source without a run call falls back to eval`() {
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            let manifest: Lint.Manifest = Lint.Manifest()
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }

    @Test
    func `Two-statement bare closure falls back to eval`() {
        // A sibling statement next to the bare bundle (even a redundant one)
        // means the active set is not provably the baked set — fall back.
        let source = """
            // swift-linter-tools-version: 0.1
            import Linter
            import Linter_Primitives_Rules

            Lint.run(dependencies: [
                .package(path: "../swift-primitives-linter-rules", products: ["Linter Primitives Rules"])
            ]) {
                Lint.Rule.Bundle.primitives
                Lint.Rule.Configuration.disable(.`raw value access`)
            }
            """
        #expect(isEvalFallback(Lint.File.Single.Classifier.classify(source: source)))
    }
}
