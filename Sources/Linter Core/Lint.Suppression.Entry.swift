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

extension Lint.Suppression {
    /// One `(line, rule-id) → reason?` record harvested from a
    /// `swift-linter:disable:next` or `swift-linter:disable:line`
    /// directive.
    public struct Entry: Sendable, Equatable {
        /// The 1-based source line whose findings for ``rule`` are
        /// suppressed.
        public let line: Text.Line.Number

        /// The rule ID whose findings on ``line`` are suppressed.
        public let rule: Lint.Rule.ID

        /// Optional REASON prose harvested from a `// REASON: ...`
        /// continuation. Recorded for observability but not consulted
        /// during finding-elision; the engine treats reasons as
        /// metadata only.
        public let reason: Swift.String?

        @inlinable
        public init(
            line: Text.Line.Number,
            rule: Lint.Rule.ID,
            reason: Swift.String? = nil
        ) {
            self.line = line
            self.rule = rule
            self.reason = reason
        }
    }
}
