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
    /// Rule-level withholding for one fix invocation.
    ///
    /// This boundary changes only fix participation. It does not alter the
    /// configuration, so excluded rules remain active for ordinary lint
    /// detection and reporting.
    public enum Exclusion {}
}
