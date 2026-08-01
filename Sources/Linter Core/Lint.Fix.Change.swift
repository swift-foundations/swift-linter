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
public import Linter_Primitives

extension Lint.Fix {
    /// One source file the fix run rewrote, with the text on both sides.
    ///
    /// Both texts are carried rather than a precomputed diff so that the
    /// reporting shape is the caller's choice and the applying path and the
    /// dry-run path emit from the same value.
    public struct Change: Sendable, Equatable {
        /// The file that was rewritten.
        public let path: File.Path

        /// The rules whose fixes contributed, in application order.
        ///
        /// A file that several rules touched lists each of them: the commit
        /// message for a fix run should be able to name what it applied.
        public let rules: [Lint.Rule.ID]

        /// The file's text before any fix ran.
        public let original: Swift.String

        /// The file's text after every participating fix ran.
        public let fixed: Swift.String

        /// Creates a change from the file, the contributing rules, and the
        /// text on both sides of the rewrite.
        @inlinable
        public init(
            path: File.Path,
            rules: [Lint.Rule.ID],
            original: Swift.String,
            fixed: Swift.String
        ) {
            self.path = path
            self.rules = rules
            self.original = original
            self.fixed = fixed
        }
    }
}

extension Lint.Fix {
    /// A rewrite the engine computed and then declined to keep, because the
    /// rewritten text did not re-parse.
    ///
    /// Reported rather than discarded: a rewriter emitting unparseable text
    /// is a defect in that rewriter, and a fix run that hid it would let the
    /// defect persist behind a clean-looking result.
    public struct Refusal: Sendable, Equatable {
        /// The file whose rewrite was refused.
        ///
        /// It is left unchanged by the refusing rule; other rules' fixes for
        /// it still apply.
        public let path: File.Path

        /// The rule whose fix produced unparseable text.
        public let rule: Lint.Rule.ID

        /// Creates a refusal from the file and the rule whose fix produced
        /// unparseable text for it.
        @inlinable
        public init(path: File.Path, rule: Lint.Rule.ID) {
            self.path = path
            self.rule = rule
        }
    }
}
