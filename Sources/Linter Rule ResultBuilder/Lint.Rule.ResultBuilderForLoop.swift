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

/// `result_builder_for_loop` — `for`-in-loop appearing directly inside the
/// trailing closure of a known result-builder constructor (Array, Set,
/// Dictionary, Buffer.Linear, Stack, Heap, Tree.Binary, etc.).
///
/// Under SE-0289's transform, every iteration of a `for` loop in a result-
/// builder body materializes a fresh `[Element]` via `buildExpression`,
/// then accumulates them into `[[Element]]` for `buildArray.flatMap`.
/// The cost is O(N) heap allocations + O(N) flatMap. At N=1000, this is
/// ~44× slower than the imperative `var a: [E] = []; for i in 0..<N {
/// a.append(i) }` pattern.
///
/// The fix is to write the sequence directly: the institute's result
/// builders ship a `buildExpression<S: Sequence>(_:)` overload (Option G
/// in `result-builder-performance-optimization.md` v2.0.0) that uses the
/// optimized `Array.init(_ sequence:)` path. At N=100, this is 0.13× of
/// imperative — i.e., the builder is 8× FASTER than the imperative form.
///
/// **Detection** is purely structural and heuristic-based: the rule
/// matches `FunctionCallExpr` whose callee identifier (after stripping
/// generic-argument clauses and joining member-access chains with `.`)
/// matches an allowlist of known institute Builder types, AND whose
/// trailing closure body contains a `ForInStmt` not nested inside another
/// closure.
///
/// The default allowlist covers the 13 institute Round-1/Round-2 Builders
/// + 5 standard-library-extensions Builders. Consumers extend it via the
/// rule's `init(severity:allowlist:)` parameter.
///
/// **Exemption**: `// swiftlint:disable:next result_builder_for_loop  //
/// reason: <citation>`. Per institute discipline, the regex-evasion
/// pattern (paren-wrap, typename-swap) is forbidden — escalate to
/// supervisor at typed-system bottom-out sites.
///
/// References:
/// - `swift-institute/Research/result-builder-performance-optimization.md`
///   (DECISION v2.0.0).
/// - `swift-institute/Experiments/result-builder-perf/` (12-case empirical
///   acceptance suite, 8/12 PASS post-fix).
extension Lint.Rule {
    public struct ResultBuilderForLoop: Lint.Rule.`Protocol` {
        public static let id: Lint.Rule.ID = "result_builder_for_loop"
        public static let defaultSeverity: Diagnostic.Severity = .warning

        /// Default allowlist: 13 institute Round-1/Round-2 Builders + 5
        /// standard-library-extensions Builders. Stored as canonical
        /// dotted identifiers ("Buffer.Linear", "Tree.N", etc.) matching
        /// the shape produced by `calleeIdentifier(of:)`.
        public static let defaultAllowlist: Set<Swift.String> = [
            // Standard Library Extensions builders
            "Array",
            "Swift.Array",
            "ContiguousArray",
            "Swift.ContiguousArray",
            "ArraySlice",
            "Swift.ArraySlice",
            "Set",
            "Swift.Set",
            "Dictionary",
            "Swift.Dictionary",
            // Institute Round-1 / Round-2 builders
            "Buffer.Linear",
            "Buffer.Ring",
            "List.Linked",
            "Stack",
            "Queue",
            "Queue.Linked",
            "Heap",
            "Set.Ordered",
            "Bitset",
            "Dictionary.Ordered",
            "Tree.Binary",
            "Tree.Unbounded",
            "Tree.N",
        ]

        public let severity: Diagnostic.Severity
        public let allowlist: Set<Swift.String>

        /// Protocol-required initializer. Uses the default allowlist;
        /// consumers needing a custom allowlist call
        /// `init(severity:allowlist:)` directly.
        @inlinable
        public init(severity: Diagnostic.Severity) {
            self.severity = severity
            self.allowlist = Self.defaultAllowlist
        }

        @inlinable
        public init() {
            self.init(severity: Self.defaultSeverity)
        }

        @inlinable
        public init(
            severity: Diagnostic.Severity = Self.defaultSeverity,
            allowlist: Set<Swift.String>
        ) {
            self.severity = severity
            self.allowlist = allowlist
        }

        public func findings(in source: Lint.Source.Parsed) -> [Lint.Finding] {
            let visitor = Visitor(
                source: source.file,
                severity: severity,
                allowlist: allowlist,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    }
}

extension Lint.Rule.ResultBuilderForLoop {
    @usableFromInline
    static let message: Swift.String =
        "`for`-loop in result-builder body materializes a fresh [Element] per "
        + "iteration (12-44x slower than imperative under SE-0289). Write the "
        + "sequence directly: `Builder { 0..<N }` instead of `Builder { for i "
        + "in 0..<N { i } }`. See "
        + "swift-institute/Research/result-builder-performance-optimization.md "
        + "(DECISION v2.0.0). If iteration is genuinely required, escalate to "
        + "supervisor and apply `// swiftlint:disable:next "
        + "result_builder_for_loop  // reason: <citation>`."

    final class Visitor: SyntaxVisitor {
        let source: Source.File
        let severity: Diagnostic.Severity
        let allowlist: Set<Swift.String>
        let converter: SourceLocationConverter
        var matches: [Lint.Finding] = []

        init(
            source: Source.File,
            severity: Diagnostic.Severity,
            allowlist: Set<Swift.String>,
            converter: SourceLocationConverter
        ) {
            self.source = source
            self.severity = severity
            self.allowlist = allowlist
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            guard let identifier = Self.calleeIdentifier(of: node.calledExpression) else {
                return .visitChildren
            }
            guard allowlist.contains(identifier) else {
                return .visitChildren
            }
            // Inspect the trailing closure first (the canonical Builder shape)
            if let trailing = node.trailingClosure,
               Self.containsForInStmt(in: trailing.statements)
            {
                emit(at: trailing.leftBrace.positionAfterSkippingLeadingTrivia)
            }
            // Inspect any non-trailing argument that's a closure literal
            for argument in node.arguments {
                if let closure = argument.expression.as(ClosureExprSyntax.self),
                   Self.containsForInStmt(in: closure.statements)
                {
                    emit(at: closure.leftBrace.positionAfterSkippingLeadingTrivia)
                }
            }
            return .visitChildren
        }

        private func emit(at position: AbsolutePosition) {
            let location = converter.location(for: position)
            matches.append(
                Lint.Finding(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: Lint.Rule.ResultBuilderForLoop.id.underlying,
                    message: Lint.Rule.ResultBuilderForLoop.message
                )
            )
        }

        /// Walks the closure's statement list, returning `true` if any
        /// `ForInStmt` is present at the closure's own scope or in nested
        /// non-closure scopes (e.g., inside an `if` or `switch`). Nested
        /// closures (which may belong to different builder contexts or be
        /// regular Swift) are skipped.
        @usableFromInline
        static func containsForInStmt(in statements: CodeBlockItemListSyntax) -> Bool {
            let detector = ForInDetector()
            detector.walk(statements)
            return detector.found
        }

        /// Extracts the dotted callee identifier from a call's
        /// `calledExpression`, stripping generic-argument clauses and
        /// joining member-access chains with `.`.
        ///
        /// Examples:
        /// - `Array<Int>` → "Array"
        /// - `Swift.Array<Int>` → "Swift.Array"
        /// - `Buffer<Int>.Linear` → "Buffer.Linear"
        /// - `Tree<Int>.N<2>` → "Tree.N"
        /// - `Set<Int>.Ordered` → "Set.Ordered"
        @usableFromInline
        static func calleeIdentifier(of expression: ExprSyntax) -> Swift.String? {
            if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
                guard let base = memberAccess.base else {
                    return nil
                }
                guard let baseIdentifier = calleeIdentifier(of: base) else {
                    return nil
                }
                return baseIdentifier + "." + memberAccess.declName.baseName.text
            }
            if let genericSpec = expression.as(GenericSpecializationExprSyntax.self) {
                return calleeIdentifier(of: genericSpec.expression)
            }
            if let declRef = expression.as(DeclReferenceExprSyntax.self) {
                return declRef.baseName.text
            }
            return nil
        }
    }

    /// Detects a `ForInStmt` in a syntax subtree, treating nested closures
    /// as opaque (a `for` inside a nested closure is in a different
    /// builder context, not the one we're inspecting).
    final class ForInDetector: SyntaxVisitor {
        var found = false

        init() {
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
            found = true
            return .skipChildren
        }

        override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
            // Don't descend into nested closures — they may have their
            // own builder context, or be regular Swift closures.
            .skipChildren
        }
    }
}
