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

public import File_System

extension Lint.Fix.Outcome {
    /// The authoritative exact-path plan, in publication order.
    public var paths: [File.Path] { changes.map(\.path) }
}
