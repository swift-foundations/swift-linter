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
import SwiftSyntax

extension Lint.Provenance.Manifest {
    /// Syntax visitor that captures the first `Package(name: "…")`
    /// argument in a SwiftPM manifest.
    ///
    /// Only a plain single-segment string literal is accepted; an
    /// interpolated or multi-segment `name:` yields no identity, which
    /// resolves toward linting at the caller.
    final class Visitor: SyntaxVisitor {
        /// The extracted package name, once visited.
        private(set) var package: Swift.String?

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            guard self.package == nil else { return .skipChildren }
            guard
                let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
                callee.baseName.text == "Package"
            else { return .visitChildren }
            for argument in node.arguments where argument.label?.text == "name" {
                guard
                    let literal = argument.expression.as(StringLiteralExprSyntax.self),
                    literal.segments.count == 1,
                    let segment = literal.segments.first?.as(StringSegmentSyntax.self)
                else { return .skipChildren }
                self.package = segment.content.text
                return .skipChildren
            }
            return .skipChildren
        }
    }
}
