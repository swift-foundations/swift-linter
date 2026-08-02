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

extension Lint.Reporter.Format {
    /// Environment channel carrying the CLI's `--format` selection to a
    /// configured linter executable.
    ///
    /// Every configured execution path converges on
    /// `Lint.run(configuration:)`: a nested `Lint/` package, the single-file
    /// eval executable, and the prebuilt standard runner. The CLI exports one
    /// token before choosing among those paths; each spawn inherits the
    /// process environment, and the shared terminal reads it before emitting
    /// findings.
    ///
    /// Unset preserves the historical `.text` default. A set-but-unrecognized
    /// token is dispatcher/executable version skew and throws instead of
    /// silently substituting text for a requested structured report.
    public enum Channel {}
}

extension Lint.Reporter.Format.Channel {
    /// The environment variable name.
    public static let variable: Swift.String = "SWIFT_LINTER_FORMAT"

    /// Encode a format for transport through the environment channel.
    public static func value(_ format: Lint.Reporter.Format) -> Swift.String {
        // swift-linter:disable:next raw value access
        // REASON: `Lint.Reporter.Format` is a String-backed wire enum; its raw
        // value is the channel token owned by this serialization boundary.
        format.rawValue
    }

    /// Read the requested report format from the process environment.
    ///
    /// - Returns: `.text` when the variable is unset; otherwise the exact
    ///   recognized format.
    /// - Throws: ``Error/invalid(value:)`` when the variable is set outside
    ///   the ``Lint/Reporter/Format`` vocabulary.
    public static func read() throws(Error) -> Lint.Reporter.Format {
        guard let raw: Swift.String = Environment.read(Self.variable) else {
            return .text
        }
        guard let format: Lint.Reporter.Format = Lint.Reporter.Format(rawValue: raw) else {
            throw .invalid(value: raw)
        }
        return format
    }
}
