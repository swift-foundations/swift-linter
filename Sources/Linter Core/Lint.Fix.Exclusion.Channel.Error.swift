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

extension Lint.Fix.Exclusion.Channel {
    /// A malformed rule-exclusion channel value.
    public enum Error: Swift.Error, Swift.Sendable {
        /// The channel value was not a JSON string array.
        case unparseable(value: Swift.String, description: Swift.String)
    }
}
