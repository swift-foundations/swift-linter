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
    /// What an `Outcome`-returning run should capture.
    ///
    /// - `.findings`: capture only surfaced findings (suppressed
    ///   findings are dropped, not surfaced).
    /// - `.suppressed`: capture only the suppressed-finding
    ///   observability stream (surfaced findings dropped).
    /// - `.all`: capture both surfaced and suppressed streams; the
    ///   pre-rename `runCapturingSuppressed` semantic.
    ///
    /// The single-word `Capture` name mirrors `Lint.Run.Policy` (Row 22
    /// of the Thread E catalog) and avoids the [API-NAME-001] compound
    /// type name (`CaptureMode`) and the [API-NAME-001a] single-type-
    /// no-namespace shape (an outer `Capture` namespace nesting only
    /// `Mode`).
    public enum Capture: Swift.String, Sendable, Hashable, CaseIterable {
        case findings
        case suppressed
        case all
    }
}
