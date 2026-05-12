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
internal import Standard_Library_Extensions
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
///
/// ## Unified single-file consumer manifest (Shape γ)
///
/// Consumers who place a single `Lint.swift` at their package root
/// (replacing the nested `Lint/` directory) declare dependencies AND
/// rule activations in one file via
/// ``run(dependencies:configuration:)``:
///
/// ```swift
/// // swift-linter-tools-version: 0.1
/// import Linter
/// import Linter_Primitives_Rules
///
/// Lint.run(dependencies: [
///     .package(path: "../../swift-primitives-linter-rules",
///              products: ["Linter Primitives Rules"]),
/// ]) {
///     Lint.Rule.Bundle.primitives
/// }
/// ```
///
/// The `dependencies:` argument is consumed syntactically by
/// swift-linter at phase 1 (AST extraction) to generate the eval
/// project's `Package.swift`; at phase 2 (compile + run) the array
/// is unused. The trailing closure is a `@Lint.Configuration.Builder`
/// over `Lint.Rule.Configuration` entries (`.enable(_:)`,
/// `.disable(_:)`, `.override(_:severity:)`) and bundle expansions
/// (`Lint.Rule.Bundle.primitives`).
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

    /// Run the linter from a single-file `Lint.swift` consumer manifest
    /// (Shape γ).
    ///
    /// The `dependencies:` argument is the value-level mirror of the
    /// SwiftPM `.package(...)` declarations swift-linter extracts
    /// syntactically at phase 1 (AST walk over `Lint.swift`). At
    /// phase 2 (`swift run --package-path <eval>`) the array is
    /// unused — the dependencies it describes have already been
    /// resolved by SwiftPM and the rule-pack products are accessible
    /// via the `import` statements at the top of the consumer's
    /// `Lint.swift`.
    public static func run(
        dependencies: [Lint.Dependency],
        @Array<Lint.Rule.Configuration>.Builder rules: () -> [Lint.Rule.Configuration]
    ) {
        _ = dependencies
        let collected: [Lint.Rule.Configuration] = rules()
        var registry: [Lint.Rule.ID: Lint.Rule] = [:]
        for entry in collected {
            registry[entry.rule.id] = entry.rule
        }
        let parent: Lint.Configuration? = Lint.SingleFile.parentConfiguration(registry: registry)
        let configuration = Lint.Configuration(inheriting: parent) { collected }
        run(configuration: configuration)
    }
}
