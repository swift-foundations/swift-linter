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

extension Lint.Run {
    /// F-A2.14 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
    /// typed `File.Path` payloads on both cases. Errors emitted from
    /// `parsedSource` carry the path-shaped value through to the
    /// reporter without an intermediate string boundary.
    public enum Error: Swift.Error, Hashable, Sendable {
        case fileNotReadable(path: File.Path)
        case nonUTF8(path: File.Path)
    }
}
