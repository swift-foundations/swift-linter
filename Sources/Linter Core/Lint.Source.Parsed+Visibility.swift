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
internal import SwiftSyntax

/// Resolve a ``Diagnostic_Primitives/Diagnostic/Record``'s 1-based
/// `(line, column)` location to the effective visibility of the
/// enclosing declaration chain in the parsed source file.
///
/// The engine layers this on top of ``Lint/Source/Parsed`` rather than
/// embedding it inside the L1 primitives because the position-math
/// (UTF-8 offset reconstruction, deepest-node walk) is engine-private
/// and only useful at finding-emission time.
extension Lint.Source.Parsed {
    /// Effective visibility of the smallest syntax node whose range
    /// contains `location` in this parsed source.
    ///
    /// Returns ``Lint/Visibility/internal`` when position lookup fails
    /// (out-of-range line:column, the location predates the first
    /// token's leading trivia, or the smallest enclosing node has no
    /// modifier in its enclosing decl chain). Swift's file-scope
    /// default is `internal`, so this fallback is conservative and
    /// non-crashing.
    ///
    /// Position math: the ``SourceLocationConverter`` exposes
    /// `position(ofLine:column:)` (the reverse of
    /// `location(for:AbsolutePosition)`), built atop its line-start
    /// cache. The walker then descends from `tree.root` and selects
    /// the deepest node whose range
    /// `[positionAfterLeadingTrivia, endPosition)` contains the
    /// target position. Once located,
    /// ``Lint/Visibility/effective(of:)`` walks the enclosing decl
    /// chain up to the source-file root and returns the minimum
    /// (narrowest) modifier encountered.
    ///
    /// Internal to `Linter Core` — this method is engine-private. The
    /// `internal import SwiftSyntax` precludes a `public` signature
    /// (would expose internally-imported types); engine callers are
    /// the only intended consumers anyway.
    internal func visibility(at location: Source.Location) -> Lint.Visibility {
        guard let position = absolutePosition(for: location) else {
            return .internal
        }
        guard let node = deepestNode(containing: position) else {
            return .internal
        }
        return Lint.Visibility.effective(of: node)
    }

    /// Reconstruct an `AbsolutePosition` from a 1-based
    /// `(line, column)` pair. SwiftSyntax 602 exposes
    /// `SourceLocationConverter.position(ofLine:column:)` which we
    /// reuse directly; this wrapper only adds the bounds guard so an
    /// out-of-range location yields `nil` rather than tripping a
    /// converter precondition.
    private func absolutePosition(for location: Source.Location) -> AbsolutePosition? {
        // Comparison stays typed via `Text.Line.Number`'s
        // `ExpressibleByIntegerLiteral` + `Comparable` conformances;
        // conversion to `Int` happens only at the SwiftSyntax boundary
        // (`SourceLocationConverter.position(ofLine:column:)` is Int-based).
        guard location.line >= 1, location.column >= 1 else { return nil }
        let lineStarts = converter.sourceLines
        guard location.line.underlying <= UInt(lineStarts.count) else { return nil }
        return converter.position(
            ofLine: Int(location.line.underlying),
            column: location.column
        )
    }

    /// Deepest syntax node whose source-accurate range
    /// `[positionAfterLeadingTrivia, endPosition)` contains
    /// `position`. Returns `nil` when no node contains the position
    /// (e.g., position is past the file's end).
    private func deepestNode(containing position: AbsolutePosition) -> Syntax? {
        let root = Syntax(tree)
        guard root.positionAfterSkippingLeadingTrivia <= position,
              position < root.endPosition else {
            return nil
        }
        var best: Syntax = root
        var cursor: Syntax = root
        // Descend greedily: at each level, pick the child whose
        // sourceRange contains `position`; record the deepest hit.
        while true {
            var descended = false
            for child in cursor.children(viewMode: .sourceAccurate) {
                if child.positionAfterSkippingLeadingTrivia <= position,
                   position < child.endPosition {
                    cursor = child
                    best = child
                    descended = true
                    break
                }
            }
            if !descended { break }
        }
        return best
    }
}
