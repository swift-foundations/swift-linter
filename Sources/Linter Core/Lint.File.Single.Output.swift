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

extension Lint.File.Single {
    /// Whether the CLI's requested output shape is one the prebuilt standard
    /// runner can faithfully reproduce.
    ///
    /// The runner (`Runner/Sources/runner/main.swift`) bakes TEXT-format
    /// diagnostics to stdout. It does NOT reshape output for
    /// `--format sarif`, so a non-text format must route to the eval fallback
    /// (see ``route(output:classification:)``) so the runner never silently
    /// substitutes its baked output for what was asked. (Note: today the
    /// eval-compiled `Lint` executable emits only text output too — Shape-γ
    /// dispatch consumers cannot yet obtain SARIF on either path; the gate
    /// keeps the constraint enforced in ONE place for when eval learns it.)
    ///
    /// The EXIT POLICY no longer participates in this gate. Both dispatched
    /// executables funnel through `Lint.run(configuration:)`, which honors
    /// the CLI-exported ``Lint/Run/Policy/Channel`` — so `--exit-policy
    /// strict` escalates identically on the fast path and the eval path, and
    /// strict requests may take the fast path. (Historically strict forced
    /// the eval fallback — which ALSO could not escalate, making CI's
    /// `--exit-policy strict` silently inert for Shape-γ consumers while
    /// paying the full eval compile. The channel closed both gaps,
    /// 2026-07-20.)
    public enum Output: Swift.Sendable, Swift.Equatable {
        /// Text format — the runner's baked format (any exit policy).
        case standard

        /// A format the prebuilt runner cannot reproduce (`--format` other
        /// than text).
        case nonStandard
    }
}
