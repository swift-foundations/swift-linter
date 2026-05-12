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

internal import File_System
public import Linter_Primitives
internal import Terminal_Primitives

/// One-call entry point for consumer `Lint` executables.
///
/// A consumer's `main.swift` collapses to a single call:
///
/// ```swift
/// import Linter
/// import Linter_Primitives_Rules
///
/// Lint.run(bundle: Lint.Rule.Bundle.primitives)
/// ```
///
/// Reads `Swift.CommandLine.arguments` (defaulting to `["."]` when no
/// paths are passed), maps them to typed ``File/Path`` values, runs
/// the engine against them, and emits findings via the text reporter
/// to stdout. Errors are printed and the process exits non-zero.
///
/// For consumers that need to mix the bundled rules with per-consumer
/// overrides — additional rules, severity overrides, path filters —
/// pass a hand-built ``Lint/Configuration``:
///
/// ```swift
/// Lint.run(configuration: Lint.Configuration {
///     Lint.Rule.Bundle.primitives
///     Lint.Rule.Configuration.override(.`try optional`, severity: .error)
/// })
/// ```
extension Lint {
    /// Run the linter with a bundle of rule configurations.
    ///
    /// Equivalent to `run(configuration: Lint.Configuration { bundle })`.
    public static func run(bundle: [Lint.Rule.Configuration]) {
        run(configuration: Lint.Configuration { bundle })
    }

    /// Run the linter with a complete configuration.
    public static func run(configuration: Lint.Configuration) {
        let arguments = Swift.CommandLine.arguments
        let pathStrings: [Swift.String] = arguments.count >= 2
            ? [Swift.String](arguments.dropFirst())
            : ["."]

        do {
            let consumerPaths: [File.Path] = try pathStrings.map { try File.Path($0) }
            let findings: [Lint.Finding] = try Lint.Run.run(paths: consumerPaths, configuration: configuration)
            Lint.Reporter.Text.emit(findings: findings, to: Terminal.Stream.stdout.write)
        } catch {
            print("[Lint] error: \(error)")
        }
    }
}
