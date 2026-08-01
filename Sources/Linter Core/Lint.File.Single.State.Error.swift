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

extension Lint.File.Single.State {
    /// A failure to materialize the state directory or its self-ignoring stamp.
    public enum Error: Swift.Error, Equatable, Sendable {
        case creationFailed(path: File.Path, description: Swift.String)
    }
}
