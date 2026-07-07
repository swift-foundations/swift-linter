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

/// Output-format reporter namespace.
///
/// Concrete reporters nest as `Lint.Reporter.<Format>` (e.g.,
/// `Lint.Reporter.Text`, `Lint.Reporter.SARIF`). The namespace is
/// shared across the Reporter Text and Reporter SARIF targets so a
/// single `Lint.Reporter.<Format>` qualified reference resolves at
/// every consumer site.
extension Lint {
    /// Namespace shared by all output-format reporters (``Reporter/Text``, ``Reporter/SARIF``).
    public enum Reporter {}
}
