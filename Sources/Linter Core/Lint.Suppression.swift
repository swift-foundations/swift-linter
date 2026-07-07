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

/// Per-source suppression map: which `(line, rule-id)` pairs should be
/// elided from findings, plus the optional `// REASON: ...` prose
/// associated with each.
///
/// Built by ``Lint/Suppression/Scanner`` from a parsed source file's
/// `Trivia` stream. Recognized directives:
///
/// - `// swift-linter:disable:next <rule-id>` — suppresses the next
///   non-blank source line for `<rule-id>`.
/// - `// swift-linter:disable:line <rule-id>` — suppresses the SAME
///   source line as the comment (trailing-comment form).
/// - `// REASON: <prose>` continuation line(s) — recorded against the
///   immediately preceding suppression directive. Not required at the
///   engine layer; a future meta-audit rule may enforce REASON
///   presence as a separate concern.
///
/// Rule IDs in directives are matched against ``Lint/Rule/ID`` values
/// (`Tagged<Lint.Rule, String>`) verbatim — the underlying string is
/// the natural-English phrase used by the rule's `id:` declaration
/// (e.g., `"unchecked call site"`). Mistyping a rule ID in a directive
/// is silently inert (no rule with that ID is suppressed); a future
/// orphan-suppression audit rule may surface unknown IDs.
extension Lint {
    /// The per-source map of `swift-linter:disable` directives harvested from
    /// comment trivia.
    public struct Suppression: Sendable, Equatable {
        /// Lines suppressed per rule ID.
        ///
        /// Keyed by `(line, rule-id)`;
        /// the value is the optional REASON prose harvested from the
        /// directive's continuation.
        public let entries: [Lint.Suppression.Entry]

        /// Creates a suppression map from its harvested entries.
        @inlinable
        public init(entries: [Lint.Suppression.Entry] = []) {
            self.entries = entries
        }
    }
}

extension Lint.Suppression {
    /// Empty suppression map — used when no directives appear in a
    /// source file. (`static` member lives in an extension, not the type
    /// body, per `[API-IMPL-008]`.)
    public static let empty: Self = Self()
}

extension Lint.Suppression {
    /// Returns whether `(line, rule)` is suppressed by this map.
    @inlinable
    public func suppresses(line: Text.Line.Number, rule: Lint.Rule.ID) -> Swift.Bool {
        for entry in entries where entry.line == line && entry.rule == rule {
            return true
        }
        return false
    }

    /// Returns the entries matching `(line, rule)` — for observability
    /// (e.g., logging which suppressions actually elided a finding).
    @inlinable
    public func entries(suppressing line: Text.Line.Number, rule: Lint.Rule.ID) -> [Entry] {
        entries.filter { $0.line == line && $0.rule == rule }
    }
}

extension Lint.Suppression {
    /// Static-prefix tokens scanned for.
    ///
    /// Centralized so the scanner
    /// and any future audit tooling agree on the syntax surface.
    fileprivate static let disableNextPrefix: Swift.String = "// swift-linter:disable:next "

    fileprivate static let disableLinePrefix: Swift.String = "// swift-linter:disable:line "

    fileprivate static let reasonPrefix: Swift.String = "// REASON:"
}

extension Lint.Suppression {
    /// Build a suppression map for `tree` using `converter` to resolve
    /// trivia positions to 1-based source lines.
    ///
    /// Walks the entire source file's leading-trivia stream, recognizing
    /// `// swift-linter:disable:next <id>` and `// swift-linter:disable:line <id>`
    /// directives. `:next` advances past blank/comment-only lines so
    /// the directive applies to the next line of CODE — matching the
    /// SwiftLint analogue's semantics.
    public static func scan(
        tree: SourceFileSyntax,
        converter: SourceLocationConverter
    ) -> Lint.Suppression {
        var entries: [Lint.Suppression.Entry] = []

        // Walk every token, harvesting directives from both leading and
        // trailing trivia. A token's `positionAfterSkippingLeadingTrivia`
        // is the source position of the token itself; the trivia
        // immediately preceding it carries comments and whitespace
        // whose start positions advance from `token.position`. The
        // trailing trivia starts at
        // `token.endPositionBeforeTrailingTrivia` and is where
        // trailing `// swift-linter:disable:line` directives appear.
        for token in tree.tokens(viewMode: .sourceAccurate) {
            scanTrivia(
                token.leadingTrivia,
                // swift-linter:disable:next raw value access
                // REASON: `token.position` is SwiftSyntax's `TokenSyntax.position`
                // (the token's `AbsolutePosition` source offset), not a Tagged-newtype
                // ordinal `.position`. The accessor-name match cannot distinguish the
                // SwiftSyntax property from the ordinal accessor it targets ([PATTERN-017]);
                // this is the legitimate SwiftSyntax boundary the trivia scanner walks from.
                tokenStartPosition: token.position,
                converter: converter,
                tree: tree,
                entries: &entries
            )
            scanTrivia(
                token.trailingTrivia,
                tokenStartPosition: token.endPositionBeforeTrailingTrivia,
                converter: converter,
                tree: tree,
                entries: &entries
            )
        }

        return Lint.Suppression(entries: entries)
    }

    fileprivate static func scanTrivia(
        _ trivia: Trivia,
        tokenStartPosition: AbsolutePosition,
        converter: SourceLocationConverter,
        tree: SourceFileSyntax,
        entries: inout [Lint.Suppression.Entry]
    ) {
        var cursor = tokenStartPosition
        // Buffer for tracking the most-recent directive so a following
        // `// REASON:` continuation attaches to it.
        var pendingReasonIndex: Swift.Int? = nil

        for piece in trivia {
            let pieceStart = cursor
            let pieceLength = piece.sourceLength
            defer { cursor = cursor.advanced(by: pieceLength.utf8Length) }

            let text: Swift.String
            switch piece {
            case .lineComment(let comment):
                text = comment

            default:
                // Whitespace and newlines between a directive and its
                // following `// REASON:` continuation are legitimate —
                // do NOT terminate the pending-reason chain here.
                // Pending-reason termination is the responsibility of
                // a NON-REASON comment (handled at the bottom of the
                // comment branch below).
                continue
            }

            let directiveLine = converter.location(for: pieceStart).line

            if text.hasPrefix(Self.disableNextPrefix) {
                let suffix = Swift.String(text.dropFirst(Self.disableNextPrefix.count))
                let ruleID = ruleIDFromDirectiveSuffix(suffix)
                let suppressedLine = nextCodeLine(
                    afterDirectiveLine: directiveLine,
                    tree: tree,
                    converter: converter
                )
                if let suppressedLine {
                    let newIndex = entries.count
                    entries.append(
                        Self.Entry(
                            line: Text.Line.Number(UInt(suppressedLine)),
                            rule: ruleID,
                            reason: nil
                        )
                    )
                    pendingReasonIndex = newIndex
                } else {
                    pendingReasonIndex = nil
                }
            } else if text.hasPrefix(Self.disableLinePrefix) {
                let suffix = Swift.String(text.dropFirst(Self.disableLinePrefix.count))
                let ruleID = ruleIDFromDirectiveSuffix(suffix)
                // `:line` targets the line carrying the directive
                // itself — typically as a trailing comment.
                let newIndex = entries.count
                entries.append(
                    Self.Entry(
                        line: Text.Line.Number(UInt(directiveLine)),
                        rule: ruleID,
                        reason: nil
                    )
                )
                pendingReasonIndex = newIndex
            } else if text.hasPrefix(Self.reasonPrefix),
                let pending = pendingReasonIndex,
                pending < entries.count
            {
                // Attach reason prose to the pending directive's entry.
                let reasonBody = Swift.String(text.dropFirst(Self.reasonPrefix.count))
                let trimmed = reasonBody.trimmingPrefixWhitespace()
                let previous = entries[pending].reason
                let combined: Swift.String
                if let previous {
                    combined = previous + " " + trimmed
                } else {
                    combined = trimmed
                }
                entries[pending] = Self.Entry(
                    line: entries[pending].line,
                    rule: entries[pending].rule,
                    reason: combined
                )
            } else {
                // Any other comment text terminates the REASON
                // continuation chain.
                pendingReasonIndex = nil
            }
        }
    }

    /// Parses the directive's suffix into a `Lint.Rule.ID`.
    ///
    /// The suffix is everything after `// swift-linter:disable:next ` or
    /// `// swift-linter:disable:line `. Trailing comments after a `//`
    /// inside the suffix would shadow the rule ID — but Swift only
    /// admits one `//` per logical comment, so the entire remaining
    /// text is the rule ID. Trim trailing whitespace.
    fileprivate static func ruleIDFromDirectiveSuffix(_ suffix: Swift.String) -> Lint.Rule.ID {
        var trimmed = suffix
        while let last = trimmed.last, last.isWhitespace {
            trimmed.removeLast()
        }
        return Lint.Rule.ID(_unchecked: trimmed)
    }

    /// Finds the next source line that contains non-comment content
    /// (i.e., a real code token), starting strictly after
    /// `directiveLine`.
    fileprivate static func nextCodeLine(
        afterDirectiveLine directiveLine: Swift.Int,
        tree: SourceFileSyntax,
        converter: SourceLocationConverter
    ) -> Swift.Int? {
        for token in tree.tokens(viewMode: .sourceAccurate) {
            let tokenLine = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
            if tokenLine > directiveLine {
                return tokenLine
            }
        }
        return nil
    }
}

extension Swift.String {
    fileprivate func trimmingPrefixWhitespace() -> Swift.String {
        var copy = self
        while let first = copy.first, first.isWhitespace {
            copy.removeFirst()
        }
        return copy
    }
}
