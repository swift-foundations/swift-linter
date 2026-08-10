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

internal import Linter_Primitives

extension Lint.Provenance {
    /// Namespace for manifest-identity extraction support — the
    /// syntax-directed read of a run root's `Package.swift` that
    /// ``Lint/Provenance/resolve(root:)`` keys the central register on.
    public enum Manifest {}
}
