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

internal import SwiftSyntax

extension Lint.File.Single {
    /// Shared recognizer for the consumer's top-level `Lint.run(...)`
    /// invocation.
    ///
    /// Both the dependency ``Extractor`` and the fast-path ``Classifier`` must
    /// locate THE SAME `Lint.run(...)` (or unqualified `run(...)`) call in the
    /// consumer's `Lint.swift` — the extractor reads its `dependencies:`
    /// argument, the classifier reads its rule-activation closure. Centralizing
    /// the recognition here guarantees they operate on the same call and
    /// removes the byte-identical `findRunCall`/`isLintRunCall` duplication that
    /// previously lived in BOTH ``Extractor`` and ``Classifier``.
    ///
    /// Named `Invocation` (not `RunCall`) per `[API-NAME-001]` — a single-word
    /// nest member rather than a compound type name.
    internal enum Invocation {}
}

extension Lint.File.Single.Invocation {
    /// Find the first top-level expression that is a `Lint.run(...)` or
    /// unqualified `run(...)` function call.
    internal static func find(in sourceFile: SourceFileSyntax) -> FunctionCallExprSyntax? {
        for item in sourceFile.statements {
            guard let expr: ExprSyntax = item.item.as(ExprSyntax.self) else { continue }
            guard let call: FunctionCallExprSyntax = expr.as(FunctionCallExprSyntax.self) else { continue }
            if isLintRunCall(call) {
                return call
            }
        }
        return nil
    }

    /// Match `Lint.run(...)` (qualified) or `run(...)` (unqualified).
    internal static func isLintRunCall(_ call: FunctionCallExprSyntax) -> Swift.Bool {
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
}
