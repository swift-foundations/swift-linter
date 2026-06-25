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
internal import Manifest_Primitives
internal import SwiftParser
internal import SwiftSyntax

extension Lint.File.Single {
    /// Syntactic fast-path / eval-fallback classifier for Shape-γ
    /// consumers (Phase 3 of
    /// `Research/near-instant-lint-with-external-rule-loading.md`).
    ///
    /// Decides whether a consumer's `Lint.swift` can be linted by the
    /// prebuilt standard runner (its active rule set is exactly the
    /// bundle the runner bakes) or must take the eval fallback. The
    /// decision is purely syntactic and **failure-safe**: any shape the
    /// runner cannot faithfully reproduce — and any parse the classifier
    /// is unsure about — yields ``Classification/evalFallback(reason:)``,
    /// so correctness never depends on the fast path being taken.
    public enum Classifier {}
}

extension Lint.File.Single.Classifier {
    /// The single bundle expression the standard runner bakes. A
    /// fast-path consumer's rule closure must be exactly this member
    /// access, with nothing applied to it and no sibling statements.
    fileprivate static let bakedBundleExpression: Swift.String = "Lint.Rule.Bundle.primitives"

    /// Classify a consumer's `Lint.swift` `source` for fast-path
    /// routing.
    ///
    /// A consumer is ``Classification/fastPathStandardBundle`` IFF BOTH:
    ///
    /// 1. It declares no `// parent:` inheritance directive. The runner's
    ///    `Lint.run(bundle:)` entry point folds no parent manifest, so a
    ///    parent chain could add or remove rules the runner does not
    ///    reflect.
    /// 2. Its `Lint.run(...)` rule closure is exactly the single
    ///    expression `Lint.Rule.Bundle.primitives` — no `.excluding`,
    ///    `.enable`, `.disable`, `.override`, and no sibling statements.
    ///
    /// Condition 2 is the load-bearing invariant: activating any inline
    /// rule, custom-pack rule, non-`primitives` bundle, or per-consumer
    /// enable/disable/exclude requires the closure to be something other
    /// than that single bare member access. So a match guarantees the
    /// consumer's *active* rule set is byte-for-byte the set the runner
    /// bakes — independent of whatever the consumer additionally imports,
    /// declares (e.g. an unused inline rule), or depends on. Rule-pack
    /// version skew between the runner's baked set and the consumer's
    /// latest-`main` set is handled separately by the runner's
    /// composite cache key ([CI-044]), not here.
    public static func classify(source: Swift.String) -> Lint.File.Single.Classification {
        Self.classify(source: source, parsed: Parser.parse(source: source))
    }

    /// Classify a consumer's `Lint.swift` from a PRE-PARSED tree, so the
    /// dispatch pipeline can parse `Lint.swift` exactly ONCE and thread the
    /// same `parsed` tree to both this classifier and the dependency
    /// ``Extractor``. `source` is still required for the byte-level
    /// `// parent:` directive scan. The public ``classify(source:)`` is a thin
    /// wrapper that parses, for callers (and tests) that hold only the text.
    internal static func classify(
        source: Swift.String,
        parsed sourceFile: SourceFileSyntax
    ) -> Lint.File.Single.Classification {
        // (1) A `// parent:` inheritance chain is not reproduced by the
        // runner. Recognise the directive with the SAME routine the parent
        // resolver uses (`Manifest.Parent.scan`) — line-anchored and bounded to
        // the leading 30 lines — rather than a raw `source.contains` substring
        // match, which would also fire on the text appearing mid-line or in a
        // string/comment far below the header. Single source of truth for the
        // directive grammar.
        if Manifest_Primitives.Manifest.Parent.scan(in: source) != nil {
            return .evalFallback(reason: "consumer declares a `// parent:` inheritance chain")
        }

        // (2) The rule closure must be exactly the baked bundle.
        guard let runCall: FunctionCallExprSyntax = Lint.File.Single.RunCall.find(in: sourceFile) else {
            return .evalFallback(reason: "no top-level `Lint.run(...)` call expression")
        }
        guard let closure: ClosureExprSyntax = Self.ruleClosure(of: runCall) else {
            return .evalFallback(reason: "`Lint.run(...)` carries no rule-activation closure")
        }
        let statements: CodeBlockItemListSyntax = closure.statements
        guard statements.count == 1,
              let only: CodeBlockItemSyntax = statements.first,
              let expression: ExprSyntax = only.item.as(ExprSyntax.self)
        else {
            return .evalFallback(reason: "rule closure is not a single expression")
        }
        // (2a) Exactly the bare baked bundle.
        if expression.as(MemberAccessExprSyntax.self) != nil,
           expression.trimmedDescription == Self.bakedBundleExpression {
            return .fastPathStandardBundle
        }
        // (2b) The baked bundle minus per-package exclusions:
        //      Lint.Rule.Bundle.primitives.excluding(rules: [ <ids> ]).
        if let disabled: Swift.Set<Lint.Rule.ID> = Self.bakedBundleExclusions(expression) {
            return .fastPathStandardBundleExcluding(disabled: disabled)
        }
        return .evalFallback(
            reason: "rule closure is not `\(Self.bakedBundleExpression)` nor `.excluding(rules:)` over it"
        )
    }

    /// If `expression` is exactly
    /// `Lint.Rule.Bundle.primitives.excluding(rules: [<ids>])` where every
    /// array element is an exactly-extractable rule ID, return the excluded ID
    /// set; otherwise `nil`.
    ///
    /// `nil` routes the consumer to the eval fallback — **never a guess**. A
    /// single unreadable element fails the whole extraction (a dropped
    /// exclusion would silently fire a rule the consumer excluded).
    fileprivate static func bakedBundleExclusions(
        _ expression: ExprSyntax
    ) -> Swift.Set<Lint.Rule.ID>? {
        guard let call: FunctionCallExprSyntax = expression.as(FunctionCallExprSyntax.self),
              let member: MemberAccessExprSyntax = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "excluding",
              let base: ExprSyntax = member.base,
              base.trimmedDescription == Self.bakedBundleExpression
        else {
            return nil
        }
        // Exactly one argument, labeled `rules:`, an array literal — no
        // trailing closure, no extra args.
        guard call.trailingClosure == nil,
              call.additionalTrailingClosures.isEmpty,
              call.arguments.count == 1,
              let argument: LabeledExprSyntax = call.arguments.first,
              argument.label?.text == "rules",
              let array: ArrayExprSyntax = argument.expression.as(ArrayExprSyntax.self)
        else {
            return nil
        }
        var ids: Swift.Set<Lint.Rule.ID> = []
        for element in array.elements {
            guard let id: Lint.Rule.ID = Self.extractRuleID(element.expression) else {
                return nil  // unreadable element → whole consumer to eval fallback
            }
            ids.insert(id)
        }
        return ids.isEmpty ? nil : ids
    }

    /// Extract a rule ID from one `.excluding(rules:)` array element. Two exact
    /// forms are recognized:
    ///   - a single-segment string literal (`"raw value access"`): the ID IS
    ///     the string content.
    ///   - a `<...>.`name`.id` member access (`Lint.Rule.`raw value access`.id`):
    ///     the ID is `name`, the rule's backtick declaration name, which equals
    ///     its `id:` string by the institute rule-naming convention (verified
    ///     across all rule packs: every `static let `X` = Lint.Rule(id: "X")`).
    /// Anything else returns `nil` (→ eval fallback; never guess).
    fileprivate static func extractRuleID(_ expression: ExprSyntax) -> Lint.Rule.ID? {
        // Form A: string literal.
        if let literal: StringLiteralExprSyntax = expression.as(StringLiteralExprSyntax.self) {
            guard literal.segments.count == 1,
                  let segment: StringSegmentSyntax = literal.segments.first?.as(StringSegmentSyntax.self)
            else { return nil }
            return Lint.Rule.ID(segment.content.text)
        }
        // Form B: `<...>.`name`.id` accessor — the component immediately before
        // `.id` is the rule name.
        if let outer: MemberAccessExprSyntax = expression.as(MemberAccessExprSyntax.self),
           outer.declName.baseName.text == "id",
           let inner: MemberAccessExprSyntax = outer.base?.as(MemberAccessExprSyntax.self) {
            let name: Swift.String = Self.unbacktick(inner.declName.baseName.text)
            return name.isEmpty ? nil : Lint.Rule.ID(name)
        }
        return nil
    }

    /// Strip surrounding backticks from a raw identifier token text if present
    /// (SwiftSyntax may retain them for a backtick-quoted identifier).
    fileprivate static func unbacktick(_ text: Swift.String) -> Swift.String {
        var slice: Swift.Substring = text[...]
        if slice.first == "`" { slice = slice.dropFirst() }
        if slice.last == "`" { slice = slice.dropLast() }
        return Swift.String(slice)
    }

    /// The rule-activation closure of a `Lint.run(...)` call — the
    /// trailing closure, or a `rules:`-labeled closure argument.
    fileprivate static func ruleClosure(of call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        if let trailing: ClosureExprSyntax = call.trailingClosure {
            return trailing
        }
        for argument in call.arguments where argument.label?.text == "rules" {
            if let closure: ClosureExprSyntax = argument.expression.as(ClosureExprSyntax.self) {
                return closure
            }
        }
        return nil
    }
}
