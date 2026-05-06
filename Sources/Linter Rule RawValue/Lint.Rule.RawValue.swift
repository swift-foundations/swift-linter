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

/// `rawValue`-misuse rule namespace.
///
/// Concrete rules nest as `Lint.Rule.RawValue.X` and target drift away
/// from the canonical preference hierarchy ([CONV-016], [INFRA-103]):
/// `.rawValue` is Tier 5 (last resort, same-package only); chained
/// access through `.rawValue` escapes the typed system.
extension Lint.Rule {
    public enum RawValue {}
}
