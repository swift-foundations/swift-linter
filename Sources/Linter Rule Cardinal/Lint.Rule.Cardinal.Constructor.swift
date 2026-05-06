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
public import SwiftSyntax

/// R2 — `Cardinal(0)` / `Cardinal(1)` constructor calls.
///
/// Subsumes the regex `cardinal_zero_one_constructor_anti_pattern`. The
/// AST predicate is `FunctionCallExprSyntax` whose callee resolves to a
/// `Cardinal` type reference (covers `Cardinal(0)`, `Cardinal.init(0)`,
/// `Cardinal<T>(0)`, `Cardinal<T>.init(0)`) and whose single unlabeled
/// argument is the integer literal `0` or `1`.
///
/// References:
/// - `swift-institute/Research/cardinal-ordinal-vector-enforcement-design.md`
///   §"R2. `Cardinal(0)` and `Cardinal(1)`"
extension Lint.Rule.Cardinal {
    public struct Constructor: Lint.Rule.`Protocol` {
        public static let id: Lint.Rule.ID = "cardinal_zero_one_constructor"
        public static let defaultSeverity: Diagnostic.Severity = .warning

        public let severity: Diagnostic.Severity

        @inlinable
        public init(severity: Diagnostic.Severity = .warning) {
            self.severity = severity
        }

        public func findings(in source: Lint.Source.Parsed) -> [Lint.Finding] {
            let visitor = Visitor(source: source.file, severity: severity, converter: source.converter)
            visitor.walk(source.tree)
            return visitor.matches
        }
    }
}

extension Lint.Rule.Cardinal.Constructor {
    @usableFromInline
    static let message: Swift.String =
        "`Cardinal(0)` / `Cardinal(1)` should use the canonical accessors `.zero` / `.one` "
        + "per [INFRA-101]. Constructor calls with literal `0` or `1` bypass the typed-system "
        + "literal discipline."

    final class Visitor: SyntaxVisitor {
        let source: Source.File
        let severity: Diagnostic.Severity
        let converter: SourceLocationConverter
        var matches: [Lint.Finding] = []

        init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
            self.source = source
            self.severity = severity
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            guard Self.calleeTypeName(node.calledExpression) == "Cardinal" else {
                return .visitChildren
            }
            guard node.arguments.count == 1, let arg = node.arguments.first else {
                return .visitChildren
            }
            guard arg.label == nil else { return .visitChildren }
            guard let lit = arg.expression.as(IntegerLiteralExprSyntax.self) else {
                return .visitChildren
            }
            guard lit.literal.text == "0" || lit.literal.text == "1" else {
                return .visitChildren
            }
            let token = node.calledExpression.firstToken(viewMode: .sourceAccurate) ?? lit.literal
            let location = converter.location(for: token.positionAfterSkippingLeadingTrivia)
            matches.append(Lint.Finding(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: Lint.Rule.Cardinal.Constructor.id.underlying,
                message: Lint.Rule.Cardinal.Constructor.message
            ))
            return .visitChildren
        }

        static func calleeTypeName(_ expr: ExprSyntax) -> Swift.String? {
            if let ref = expr.as(DeclReferenceExprSyntax.self) {
                return ref.baseName.text
            }
            if let generic = expr.as(GenericSpecializationExprSyntax.self) {
                return calleeTypeName(generic.expression)
            }
            if let member = expr.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "init",
               let base = member.base {
                return calleeTypeName(base)
            }
            return nil
        }
    }
}
