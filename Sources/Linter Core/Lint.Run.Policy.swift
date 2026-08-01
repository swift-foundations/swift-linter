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

public import Linter_Primitives

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

extension Lint.Run.Policy {
    /// Whether this policy turns `findings` into a non-zero process result.
    ///
    /// Strict remains deliberately narrower than
    /// ``Lint/Run/Outcome/violations``: warnings count in the headline total,
    /// while only errors gate a strict invocation. Notes and remarks are
    /// rendered prompts and never participate in either decision.
    public func fails(for findings: [Lint.Finding]) -> Swift.Bool {
        switch self {
        case .advisory: false
        case .strict:
            findings.contains { $0.record.severity == .error }
        }
    }
}
