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

extension Lint.Fix.Scope.Manifest.Channel {
    /// A malformed manifest-path channel value.
    public enum Error: Swift.Error, Swift.Sendable {
        /// The channel value was not a JSON string.
        case unparseable(value: Swift.String, description: Swift.String)

        /// The decoded string was not a valid typed path.
        case invalid(path: Swift.String, description: Swift.String)
    }
}
