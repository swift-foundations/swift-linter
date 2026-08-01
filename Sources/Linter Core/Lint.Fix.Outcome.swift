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

public import File_System

extension Lint.Fix {
    /// The result of a fix run.
    ///
    /// Carries the counts a caller needs to tell "nothing needed fixing"
    /// apart from "nothing could have been fixed": a run where
    /// ``fixableRules`` is zero loaded no rewriter-backed rule at all, and
    /// its empty ``changes`` says nothing whatsoever about the tree. That is
    /// the same measurement discipline the lint summary applies, for the
    /// same reason — a zero from a run that was never configured is not a
    /// zero anyone may act on.
    public struct Outcome: Sendable, Equatable {
        /// One entry per planned whole-file replacement.
        public let changes: [Change]

        /// The exact paths actually replaced by an applying run.
        ///
        /// This is empty for a dry run and when a parse refusal prevents the
        /// plan from reaching the publication phase.
        public let published: [File.Path]

        /// Rewrites the engine refused because they did not re-parse.
        public let refusals: [Refusal]

        /// How many source files the run read and considered.
        public let filesScanned: Swift.Int

        /// How many activated rules declared a canonical fix.
        ///
        /// Zero means this configuration has no autofix capability at all.
        public let fixableRules: Swift.Int

        /// Creates an outcome from the rewrites, the refusals, and the counts
        /// that say whether the run could have rewritten anything at all.
        @inlinable
        public init(
            changes: [Change] = [],
            published: [File.Path] = [],
            refusals: [Refusal] = [],
            filesScanned: Swift.Int = 0,
            fixableRules: Swift.Int = 0
        ) {
            self.changes = changes
            self.published = published
            self.refusals = refusals
            self.filesScanned = filesScanned
            self.fixableRules = fixableRules
        }
    }
}
