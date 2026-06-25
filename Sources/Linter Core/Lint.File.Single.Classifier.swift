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
        // (1) A `// parent:` inheritance chain is not reproduced by the
        // runner. Reject conservatively before any parsing.
        if source.contains("// parent:") {
            return .evalFallback(reason: "consumer declares a `// parent:` inheritance chain")
        }

        // (2) The rule closure must be exactly the baked bundle.
        let sourceFile: SourceFileSyntax = Parser.parse(source: source)
        guard let runCall: FunctionCallExprSyntax = Self.findRunCall(in: sourceFile) else {
            return .evalFallback(reason: "no top-level `Lint.run(...)` call expression")
        }
        guard let closure: ClosureExprSyntax = Self.ruleClosure(of: runCall) else {
            return .evalFallback(reason: "`Lint.run(...)` carries no rule-activation closure")
        }
        let statements: CodeBlockItemListSyntax = closure.statements
        guard statements.count == 1,
              let only: CodeBlockItemSyntax = statements.first,
              let expression: ExprSyntax = only.item.as(ExprSyntax.self),
              expression.as(MemberAccessExprSyntax.self) != nil,
              expression.trimmedDescription == Self.bakedBundleExpression
        else {
            return .evalFallback(
                reason: "rule closure is not exactly `\(Self.bakedBundleExpression)`"
            )
        }
        return .fastPathStandardBundle
    }

    /// Find the first top-level `Lint.run(...)` / `run(...)` call. Mirrors
    /// the recognition in ``Lint/File/Single/Extractor`` so the same call
    /// the dependency extractor reads is the one classified.
    fileprivate static func findRunCall(in sourceFile: SourceFileSyntax) -> FunctionCallExprSyntax? {
        for item in sourceFile.statements {
            guard let expr: ExprSyntax = item.item.as(ExprSyntax.self) else { continue }
            guard let call: FunctionCallExprSyntax = expr.as(FunctionCallExprSyntax.self) else { continue }
            if Self.isLintRunCall(call) {
                return call
            }
        }
        return nil
    }

    /// Match `Lint.run(...)` (qualified) or `run(...)` (unqualified).
    fileprivate static func isLintRunCall(_ call: FunctionCallExprSyntax) -> Swift.Bool {
        if let member: MemberAccessExprSyntax = call.calledExpression.as(MemberAccessExprSyntax.self) {
            guard member.declName.baseName.text == "run" else { return false }
            guard let base: DeclReferenceExprSyntax = member.base?.as(DeclReferenceExprSyntax.self) else {
                return true
            }
            return base.baseName.text == "Lint"
        }
        if let ref: DeclReferenceExprSyntax = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text == "run"
        }
        return false
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
