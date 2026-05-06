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

/// Cardinal-domain rule namespace.
///
/// Concrete rules nest as `Lint.Rule.Cardinal.X` and target drift away
/// from the high-typed `Cardinal` discipline ([INFRA-101], [INFRA-200]).
extension Lint.Rule {
    public enum Cardinal {}
}
