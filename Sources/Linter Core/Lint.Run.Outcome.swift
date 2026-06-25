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
    /// Outcome of a lint run that distinguishes the surfaced findings
    /// from those elided by per-finding ``Lint/Suppression`` directives.
    ///
    /// Both fields carry ``Lint/Finding`` values rather than bare
    /// ``Diagnostic_Primitives/Diagnostic/Record`` — the engine computes
    /// the effective visibility of each finding's enclosing decl chain
    /// via ``Lint/Source/Parsed/visibility(at:)`` and pairs it with the
    /// rule-emitted record. Consumers that only need the underlying
    /// record access `finding.record` directly.
    public struct Outcome: Sendable, Equatable {
        /// Findings the engine surfaces to the caller — survived
        /// per-source ``Lint/Suppression`` consultation. Each finding
        /// pairs the rule-emitted ``Diagnostic_Primitives/Diagnostic/Record``
        /// with the effective ``Lint/Visibility`` of its enclosing decl.
        public let findings: [Lint.Finding]

        /// Findings the engine elided because a `swift-linter:disable`
        /// directive matched. Recorded for observability; never the
        /// engine's exit-policy signal. Visibility is computed for
        /// suppressed findings too — empirical follow-ups can segment
        /// the suppressed stream by visibility the same way as the
        /// surfaced one.
        public let suppressed: [Lint.Finding]

        /// The number of source files the walker visited and the engine
        /// parsed this run. Powers the always-on run summary (the
        /// "<files linted>" field) so a clean run is self-evidently a real
        /// run rather than a silent no-op.
        // swift-linter:disable:next compound identifier
        // REASON: a stored scalar count on the public Outcome value type; a nested-accessor
        // rename (`files.linted`) is disproportionate for an Int and would churn the public
        // Outcome API + the run-summary call sites without improving the surface ([API-NAME-002]).
        public let filesLinted: Swift.Int

        @inlinable
        public init(
            findings: [Lint.Finding] = [],
            suppressed: [Lint.Finding] = [],
            filesLinted: Swift.Int = 0
        ) {
            self.findings = findings
            self.suppressed = suppressed
            self.filesLinted = filesLinted
        }
    }
}
