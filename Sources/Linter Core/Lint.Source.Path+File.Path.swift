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
public import Linter_Primitives

extension Lint.Source.Path {
    /// Typed conversion from L3 ``File_System/File/Path`` to the L1
    /// ``Linter_Primitives/Lint/Source/Path``.
    ///
    /// The mechanism — extracting the underlying string via
    /// ``Paths/Path/description`` — is encapsulated here per [IMPL-010].
    /// Call sites read `Lint.Source.Path(filePath)`, surfacing intent
    /// rather than mechanism.
    @inlinable
    public init(_ filePath: File.Path) {
        self = Self(filePath.description)
    }
}
