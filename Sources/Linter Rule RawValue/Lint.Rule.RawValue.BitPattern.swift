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

/// R4 — `X(bitPattern: …rawValue)` integration-overload anti-pattern.
///
/// Subsumes the regex `bitpattern_rawvalue_chain_anti_pattern`. The AST
/// predicate is a `FunctionCallExprSyntax` carrying a `bitPattern:`
/// labeled argument whose expression chains through a `.rawValue`
/// member access (anywhere inside the argument expression).
///
/// Typename-swap evasion (`Int(bitPattern:)` vs `UInt(bitPattern:)` vs
/// `self.init(bitPattern:)` vs `Int.init(bitPattern:)` vs
/// `Int8(bitPattern:)` …) is closed natively: every form parses to a
/// `FunctionCallExprSyntax` carrying the same labeled argument. The
/// predicate doesn't constrain the callee, so all spellings hit.
///
/// References:
/// - `swift-institute/Research/cardinal-ordinal-vector-enforcement-design.md`
///   §"R4. `Int(bitPattern: <something>.rawValue ...)`"
/// - `swift-institute/Research/swiftsyntax-based-custom-linter-investigation.md`
///   §"Q2 — Evasion-class closure matrix" (typename-swap row)
extension Lint.Rule.RawValue {
    public struct BitPattern: Lint.Rule.`Protocol` {
        public static let id: Lint.Rule.ID = "bitpattern_rawvalue_chain"
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

extension Lint.Rule.RawValue.BitPattern {
    @usableFromInline
    static let message: Swift.String =
        "`init(bitPattern:)` whose argument chains through `.rawValue` — including "
        + "`Int(...)`, `UInt(...)`, `Int.init(...)`, `self.init(...)`, and other syntactic "
        + "equivalents — bypasses the canonical preference hierarchy. Prefer `.retag()` / "
        + "`.map()` (Tier 1/2 of [CONV-016]) before resorting to the [INFRA-002] "
        + "integration overload — and when you do use the overload, pass the typed value "
        + "directly: `Int(bitPattern: foo)` not `Int(bitPattern: foo.rawValue)`. If this "
        + "site IS the [INFRA-002] integration overload definition itself, escalate to "
        + "supervisor and apply "
        + "`// swiftlint:disable:next bitpattern_rawvalue_chain  // reason: <citation>`."

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
            for arg in node.arguments {
                guard let label = arg.label, label.text == "bitPattern" else { continue }
                guard Self.containsRawValueAccess(arg.expression) else { continue }
                let location = converter.location(for: label.positionAfterSkippingLeadingTrivia)
                matches.append(Lint.Finding(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: Lint.Rule.RawValue.BitPattern.id.underlying,
                    message: Lint.Rule.RawValue.BitPattern.message
                ))
            }
            return .visitChildren
        }

        static func containsRawValueAccess(_ expr: ExprSyntax) -> Bool {
            let finder = RawValueFinder(viewMode: .sourceAccurate)
            finder.walk(expr)
            return finder.found
        }
    }

    final class RawValueFinder: SyntaxVisitor {
        var found = false

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if node.declName.baseName.text == "rawValue" {
                found = true
            }
            return .visitChildren
        }
    }
}
