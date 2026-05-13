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
    /// How the linter's exit code reacts to emitted findings.
    ///
    /// - `.advisory`: emit findings; exit 0 unconditionally.
    /// - `.strict`: emit findings; exit non-zero when any finding has
    ///   severity `.error`.
    ///
    /// Phase 1 / 1.5 carried this as a `Bool strict` flag in the CLI;
    /// Phase 1.6 promotes it to a typed enum so future policies
    /// (`.warningsAsErrors`, `.thresholdCount(_:)`, `.severityFloor(_:)`)
    /// extend the closed vocabulary without flag explosion.
    public enum Policy: Swift.String, Sendable, Hashable, CaseIterable {
        case advisory
        case strict
    }
}
