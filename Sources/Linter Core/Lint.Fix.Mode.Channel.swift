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

extension Lint.Fix.Mode {
    /// Environment channel carrying the CLI's `--fix` request to the
    /// dispatched executables.
    ///
    /// The same terminal the exit-policy channel uses, for the same reason:
    /// both Shape-γ dispatch targets — the prebuilt standard runner and the
    /// eval-compiled consumer executable — funnel through
    /// `Lint.run(configuration:)`, which reads this channel. A flag on the
    /// dispatcher's argument vector would reach neither, because the
    /// dispatched executable reads only lint-target paths from its
    /// arguments; a path-shaped `--fix` would be read as a path.
    ///
    /// Unset ⇒ `nil`, which is an ordinary lint run — the behaviour of every
    /// invocation that predates this flag. SET-but-unrecognized fails loud:
    /// a machine-set channel carrying an unknown token is version skew
    /// between coordinator and dispatched executable, and the failure mode
    /// on this channel is worse than on any other one — silently falling
    /// back to a lint run would report findings while the caller believes it
    /// applied fixes, and silently falling back to `apply` would write over
    /// a tree the caller asked only to preview.
    public enum Channel {}
}

extension Lint.Fix.Mode.Channel {
    /// The environment variable name.
    public static let variable: Swift.String = "SWIFT_LINTER_FIX"

    /// Read the fix mode from the process environment.
    ///
    /// - Returns: the parsed mode, or `nil` when the variable is unset
    ///   (an ordinary lint run).
    /// - Throws: ``Error/invalid(value:)`` when set outside the
    ///   ``Lint/Fix/Mode`` vocabulary.
    public static func read() throws(Error) -> Lint.Fix.Mode? {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return nil
        }
        guard let mode: Lint.Fix.Mode = Lint.Fix.Mode(rawValue: raw) else {
            throw .invalid(value: raw)
        }
        return mode
    }
}

extension Lint.Fix.Mode.Channel {
    /// A channel value outside the ``Lint/Fix/Mode`` vocabulary.
    public enum Error: Swift.Error, Hashable, Sendable {
        case invalid(value: Swift.String)
    }
}
