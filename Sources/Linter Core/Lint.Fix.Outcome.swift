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

        /// Fix-capable active rules withheld from this fix invocation.
        ///
        /// An excluded rule remains active for ordinary lint detection. It is
        /// absent here only because its whole-file rewrite was withheld.
        public let excludedRules: [Lint.Rule.ID]

        /// Rules that contributed a parse-valid rewrite to the planned files.
        ///
        /// This reports rule-level participation independently of whether an
        /// applying run subsequently publishes the plan.
        public let plannedRules: [Lint.Rule.ID]

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
            excludedRules: [Lint.Rule.ID] = [],
            plannedRules: [Lint.Rule.ID] = [],
            published: [File.Path] = [],
            refusals: [Refusal] = [],
            filesScanned: Swift.Int = 0,
            fixableRules: Swift.Int = 0
        ) {
            self.changes = changes
            self.excludedRules = excludedRules
            self.plannedRules = plannedRules
            self.published = published
            self.refusals = refusals
            self.filesScanned = filesScanned
            self.fixableRules = fixableRules
        }
    }
}
