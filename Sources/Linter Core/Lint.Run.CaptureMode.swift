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
    public enum CaptureMode: Swift.String, Sendable, Hashable, CaseIterable {
        case findings
        case suppressed
        case all
    }
}
