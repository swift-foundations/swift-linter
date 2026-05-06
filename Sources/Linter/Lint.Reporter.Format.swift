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

extension Lint.Reporter {
    /// The output format produced by a linter run.
    ///
    /// Closed enum: `.text` (SwiftLint-compatible textual lines, the
    /// default) or `.sarif` (SARIF 2.1.0 JSON document, for CI artifact
    /// upload).
    ///
    /// Phase 1 / 1.5 carried this as a `Bool sarif` flag in the CLI;
    /// Phase 1.6 promotes it to a typed enum so future formats
    /// (`.githubActions`, `.junit`, `.checkstyle`) extend the closed
    /// vocabulary without flag explosion.
    public enum Format: Swift.String, Sendable, Hashable, CaseIterable {
        case text
        case sarif
    }
}
