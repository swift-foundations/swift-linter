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
    /// The runner (`Runner/Sources/runner/main.swift`) bakes a single output
    /// shape: text-format diagnostics to stdout with an advisory exit. It does
    /// NOT reshape output for `--format sarif`, and it does NOT escalate the
    /// exit code for `--exit-policy strict`. The fast path may therefore only
    /// be taken when the consumer requested exactly that shape; any other
    /// request must route to the eval fallback (see
    /// ``route(output:classification:)``) so the runner never silently
    /// substitutes its baked output for what was asked.
    ///
    /// Note: today the eval-compiled `Lint` executable also emits only
    /// text/advisory output — single-file (Shape γ) dispatch consumers cannot
    /// yet obtain SARIF / strict-exit at all, a pre-existing limitation of the
    /// dispatch architecture (the consumer's `Lint.run` reads only lint-target
    /// paths from `CommandLine.arguments`). This gate is the fast path
    /// correctly declining responsibility it cannot fulfill, so that the moment
    /// the dispatched executable learns to honor those flags the constraint is
    /// already enforced in ONE place — never a fast-path-only divergence.
    public enum Output: Swift.Sendable, Swift.Equatable {
        /// Text format, advisory exit — exactly the runner's baked shape.
        case standard

        /// A format or exit policy the prebuilt runner cannot reproduce
        /// (`--format` other than text, or a non-advisory `--exit-policy`).
        case nonStandard
    }
}
