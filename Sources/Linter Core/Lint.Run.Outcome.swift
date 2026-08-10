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
        /// per-source ``Lint/Suppression`` consultation.
        ///
        /// Each finding
        /// pairs the rule-emitted ``Diagnostic_Primitives/Diagnostic/Record``
        /// with the effective ``Lint/Visibility`` of its enclosing decl.
        public let findings: [Lint.Finding]

        /// Findings the engine elided because a `swift-linter:disable`
        /// directive matched.
        ///
        /// Recorded for observability; never the
        /// engine's exit-policy signal. Visibility is computed for
        /// suppressed findings too — empirical follow-ups can segment
        /// the suppressed stream by visibility the same way as the
        /// surfaced one.
        public let suppressed: [Lint.Finding]

        // swift-linter:disable:next compound identifier
        // REASON: a stored scalar count on the public Outcome value type; a nested-accessor
        // rename (`files.linted`) is disproportionate for a count and would churn the public
        // Outcome API + the run-summary call sites without improving the surface ([API-NAME-002]).
        /// The number of source files the walker visited and the engine
        /// parsed this run.
        ///
        /// Powers the always-on run summary (the
        /// "<files linted>" field) so a clean run is self-evidently a real
        /// run rather than a silent no-op.
        ///
        /// A bare `Int`: a display-only count formatted into the one-line run
        /// summary, never indexed or arithmetic-combined beyond a `+= 1` walk
        /// tally. Typing it (`Count`/`Index<Element>.Count`) would pull a
        /// cardinal/collection dependency tree into the engine for no semantic
        /// gain — leanness wins for a display value.
        public let filesLinted: Swift.Int

        // swift-linter:disable:next compound identifier
        // REASON: a stored scalar count on the public Outcome value type, the same
        // shape and rationale as `filesLinted` above ([API-NAME-002]).
        /// The number of source files the walker visited that a centrally
        /// declared vendored-fork provenance entry exempted from this
        /// run's input (swift-foundations/swift-linter#45).
        ///
        /// Recorded for observability, so a run over a declared fork
        /// states how much of the walked tree was vendored scope rather
        /// than silently shrinking `filesLinted`. Zero everywhere except
        /// a declared fork's own run.
        public let filesExempted: Swift.Int

        /// Creates an outcome from its constituent finding streams and file counts.
        @inlinable
        public init(
            findings: [Lint.Finding] = [],
            suppressed: [Lint.Finding] = [],
            filesLinted: Swift.Int = 0,
            filesExempted: Swift.Int = 0
        ) {
            self.findings = findings
            self.suppressed = suppressed
            self.filesLinted = filesLinted
            self.filesExempted = filesExempted
        }
    }
}

extension Lint.Run.Outcome {
    /// Surfaced findings that require remediation.
    ///
    /// Errors and warnings are violations. Notes and remarks remain surfaced
    /// diagnostic context, but are prompts rather than violations: they do not
    /// contribute to headline totals. This is the engine's one typed boundary
    /// between a rule's ``Diagnostic_Primitives/Diagnostic/Severity`` and
    /// every consumer that aggregates a run.
    ///
    /// A rule pack selects this behavior by declaring its rule's existing
    /// typed default severity as `.note`; no string class or package-local
    /// counting override is involved.
    public var violations: [Lint.Finding] {
        findings.filter { finding in
            switch finding.record.severity {
            case .error, .warning: true
            case .note, .remark: false
            }
        }
    }
}
