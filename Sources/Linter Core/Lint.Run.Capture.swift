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

/// Namespace for capture-related types on ``Lint/Run``.
///
/// Currently nests only ``Mode``; future siblings (e.g.,
/// `Capture.Filter`, `Capture.Strategy`) extend the namespace
/// without API churn. The Nest.Name shape (``Capture/Mode``) is
/// preferred over a top-level compound type name (`CaptureMode`)
/// per [API-NAME-001].
extension Lint.Run {
    public enum Capture {}
}
