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

extension Lint.Run {
    public enum Error: Swift.Error, Hashable, Sendable {
        case fileNotReadable(path: Swift.String)
        case nonUTF8(path: Swift.String)
    }
}
