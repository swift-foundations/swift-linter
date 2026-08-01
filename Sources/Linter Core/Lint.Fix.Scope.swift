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

extension Lint.Fix {
    /// The manifest-supplied boundary within which fixes may be applied.
    ///
    /// A lint run may inspect the whole package so findings in manifests,
    /// maintenance scripts, fixtures, and other non-target Swift files remain
    /// visible. Fix application is narrower: only files below one of the exact
    /// target roots supplied by the caller are eligible. The linter never
    /// infers target membership from directory names.
    public enum Scope {}
}
