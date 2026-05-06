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
public import SwiftOperators

/// R1 — `count - 1` and its semantically-equivalent rewrites.
///
/// Subsumes the regex pair `cardinal_count_minus_one_anti_pattern` +
/// `cardinal_count_minus_one_evasion`. After operator folding the four
/// surface-text variants collapse to two AST predicates:
///
/// 1. **Subtraction with literal `1`** — an `InfixOperatorExprSyntax`
///    whose operator is `-`, whose right operand is the integer literal
///    `1`, and whose left operand contains an identifier `count`.
///    Catches the base `count - 1`, paren-wrapped `(count) - 1`,
///    cast-outside `Double(seq.count) - 1`, and operand-reorder
///    `count - i - 1` (left-associativity makes the outer `- 1`
///    binary-bind to a left subtree that contains `count`).
///
/// 2. **Algebraic-flip via comparison** — an `InfixOperatorExprSyntax`
///    whose operator is one of `<`, `<=`, `==`, `!=`, `>=`, `>`, where
///    one side has the shape `<expr> + 1` (commutative) and the other
///    side contains an identifier `count`. Catches `i + 1 < count`,
///    `1 + i < count`, `count == i + 1`, etc.
///
/// Operand-reorder `(count - i - 1)` — uncatchable by regex — is
/// caught by predicate 1: left-associativity parses the subexpression
/// as `((count - i) - 1)`, whose outer `-` has RHS `1` and LHS
/// `count - i` (which contains `count`).
///
/// Comments-as-code is a non-issue at the AST level: comments are
/// `Trivia`, not part of the expression grammar; the visitor never
/// reaches them.
///
/// References:
/// - `swift-institute/Research/cardinal-ordinal-vector-enforcement-design.md`
///   §"R1. `count - 1` and family"
/// - `swift-institute/Research/swiftsyntax-based-custom-linter-investigation.md`
///   §"Q3 — Deferred AST-rule unblocking matrix"
extension Lint.Rule.Cardinal {
    public struct Count: Lint.Rule.`Protocol` {
        public static let id: Lint.Rule.ID = "cardinal_count_minus_one"
        public static let defaultSeverity: Diagnostic.Severity = .warning

        public let severity: Diagnostic.Severity

        @inlinable
        public init(severity: Diagnostic.Severity = .warning) {
            self.severity = severity
        }

        public func findings(in source: Lint.Source.Parsed) -> [Lint.Finding] {
            let folded = OperatorTable.standardOperators.foldAll(source.tree, errorHandler: { _ in })
            let visitor = Visitor(source: source.file, severity: severity, converter: source.converter)
            visitor.walk(folded)
            return visitor.matches
        }
    }
}

extension Lint.Rule.Cardinal.Count {
    @usableFromInline
    static let message: Swift.String =
        "`count - 1` (or syntactic equivalents — paren-wrap `(count) - 1`, cast-outside "
        + "`Double(seq.count) - 1`, algebraic-flip `+ 1 [<=] count`, operand-reorder "
        + "`count - i - 1`) indicates `count: Int` not `count: Cardinal` (the typed form "
        + "would not compile per [INFRA-200]). Use `.subtract.saturating(.one)` / "
        + "`.subtract.exact(.one)` / typed `count - .one` per [INFRA-025], or for "
        + "stdlib-Int sites where no typed surface is available either (α) use the "
        + "stdlib's named idiom for the concept (`indices.dropLast()`, `.last`, "
        + "`endIndex - 1`) or (β) escalate to supervisor and apply "
        + "`// swiftlint:disable:next cardinal_count_minus_one  // reason: <citation>`."

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

        override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
            guard let binOp = node.operator.as(BinaryOperatorExprSyntax.self) else {
                return .visitChildren
            }
            let opText = binOp.operator.text

            if opText == "-",
               Self.isLiteralOne(node.rightOperand),
               Self.containsCountIdentifier(node.leftOperand) {
                report(at: binOp.operator)
                return .visitChildren
            }

            if Self.isComparisonOperator(opText) {
                if Self.isPlusOne(node.leftOperand), Self.containsCountIdentifier(node.rightOperand) {
                    report(at: binOp.operator)
                } else if Self.isPlusOne(node.rightOperand), Self.containsCountIdentifier(node.leftOperand) {
                    report(at: binOp.operator)
                }
            }

            return .visitChildren
        }

        func report(at token: TokenSyntax) {
            let location = converter.location(for: token.positionAfterSkippingLeadingTrivia)
            matches.append(Lint.Finding(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: Lint.Rule.Cardinal.Count.id.underlying,
                message: Lint.Rule.Cardinal.Count.message
            ))
        }

        static func isLiteralOne(_ expr: ExprSyntax) -> Bool {
            guard let lit = expr.as(IntegerLiteralExprSyntax.self) else { return false }
            return lit.literal.text == "1"
        }

        static func isComparisonOperator(_ text: Swift.String) -> Bool {
            switch text {
            case "<", "<=", "==", "!=", ">=", ">": return true
            default: return false
            }
        }

        static func isPlusOne(_ expr: ExprSyntax) -> Bool {
            guard let infix = expr.as(InfixOperatorExprSyntax.self),
                  let binOp = infix.operator.as(BinaryOperatorExprSyntax.self),
                  binOp.operator.text == "+"
            else { return false }
            return isLiteralOne(infix.leftOperand) || isLiteralOne(infix.rightOperand)
        }

        static func containsCountIdentifier(_ expr: ExprSyntax) -> Bool {
            for token in expr.tokens(viewMode: .sourceAccurate) {
                if case .identifier(let name) = token.tokenKind, name == "count" {
                    return true
                }
            }
            return false
        }
    }
}
