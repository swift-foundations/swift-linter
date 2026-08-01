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

extension Lint.Rule.Bundle.Baked.Channel {
    /// A set-but-unrecognized channel value.
    public enum Error: Swift.Error, Swift.Equatable {
        case invalid(value: Swift.String)
    }
}
