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

internal import Environment

extension Lint.Run.Policy {
    /// Environment channel carrying the CLI's `--exit-policy` to the
    /// dispatched executables.
    ///
    /// Both Shape-γ dispatch targets — the prebuilt standard runner
    /// (`Lint.run(bundle:)`) and the eval-compiled consumer executable
    /// (`Lint.run(dependencies:rules:)`) — funnel through
    /// `Lint.run(configuration:)`, which reads this channel and escalates the
    /// exit code for `.strict` (non-zero when any finding has severity
    /// `.error`). The swift-linter CLI exports the variable before dispatch;
    /// both spawn paths inherit the process environment (the runner spawn
    /// inherits or snapshots it; the eval spawn likewise), so ONE export
    /// covers both.
    ///
    /// Before this channel existed, `--exit-policy strict` was silently inert
    /// for every Shape-γ consumer: the dispatched executable read only
    /// lint-target paths from `CommandLine.arguments` and always exited
    /// advisory. The fast-path router therefore forced strict requests to the
    /// eval fallback ("an output shape the runner cannot produce") — which
    /// ALSO could not produce it. The channel closes both gaps at the single
    /// shared terminal.
    ///
    /// Unset ⇒ `nil` (caller applies the advisory default — the local-run and
    /// pre-rollout behavior). SET-but-unrecognized fails loud via
    /// ``Error/invalid(value:)``: a machine-set channel carrying an unknown
    /// token is version skew between coordinator and dispatched executable,
    /// and linting with a silently-weakened exit policy would be a
    /// wrong-result-that-exits-0 hazard (mirrors the selection / parent
    /// channel discipline).
    public enum Channel {
        /// The environment variable name.
        public static let variable: Swift.String = "SWIFT_LINTER_EXIT_POLICY"

        /// A set-but-unrecognized channel value.
        public enum Error: Swift.Error, Swift.Equatable {
            case invalid(value: Swift.String)
        }

        /// Read the exit policy from the process environment.
        ///
        /// - Returns: the parsed policy, or `nil` when the variable is unset.
        /// - Throws: ``Error/invalid(value:)`` when set to a value outside the
        ///   ``Lint/Run/Policy`` vocabulary.
        public static func read() throws(Error) -> Lint.Run.Policy? {
            guard let raw: Swift.String = Environment.read(Self.variable) else {
                return nil
            }
            guard let policy: Lint.Run.Policy = Lint.Run.Policy(rawValue: raw) else {
                throw .invalid(value: raw)
            }
            return policy
        }
    }
}
