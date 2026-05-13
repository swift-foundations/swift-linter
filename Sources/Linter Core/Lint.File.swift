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

/// Namespace for file-scoped consumer-manifest mechanisms.
///
/// Currently hosts ``Lint/File/Single`` — the single-file Shape-γ
/// consumer manifest detection + dispatch path. Sibling concepts
/// (multi-file manifests, alternate single-file shapes) can compose
/// under this namespace as they emerge.
///
/// Decomposed from the prior `Lint.SingleFile` compound-name shape per
/// `[API-NAME-001]` Nest.Name. The Thread-E-catalog Row 24 disposition
/// target is `Lint.File.Single`.
extension Lint {
    public enum File: Swift.Sendable {}
}
