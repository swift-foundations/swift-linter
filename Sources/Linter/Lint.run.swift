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
internal import Process
public import SPM_Standard
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
///     .package(
///         path: "../swift-primitives-linter-rules",
///         products: ["Linter Primitives Rules"]
///     ),
/// ]) {
///     Lint.Rule.Bundle.primitives
/// }
/// ```
///
/// The `dependencies:` argument carries typed `Package.Dependency`
/// values (the L2 SwiftPM-flavored dependency abstraction from
/// swift-spm-standard). The `.package(path:products:)` /
/// `.package(url:_:products:)` / `.package(url:from:products:)`
/// shorthand factories at
/// ``Package/Dependency/package(path:products:)`` mirror SwiftPM's
/// `PackageDescription.Package.Dependency.package(...)` call-site
/// shape — that's the syntactic form swift-linter's phase 1 AST
/// extractor recognizes when generating the eval project's
/// `Package.swift`. At phase 2 (compile + run) the array is unused.
/// The trailing closure is a `@Lint.Configuration.Builder` over
/// `Lint.Rule.Configuration` entries (`.enable(_:)`,
/// `.disable(_:)`, `.override(_:severity:)`) and bundle expansions
/// (`Lint.Rule.Bundle.primitives`).
extension Lint {
    /// Run the linter with a bundle of rule configurations.
    ///
    /// Equivalent to `run(configuration: Lint.Configuration { bundle })`,
    /// EXCEPT when a runtime selection manifest is provisioned (the Phase-3
    /// fast path — `SWIFT_LINTER_SELECTION_MANIFEST`). A pure-bundle consumer
    /// that activates `Bundle.primitives.excluding(rules: [...])` is routed to
    /// the prebuilt standard runner (which bakes the *full* bundle); the CLI
    /// passes the consumer's exclusions as a ``Lint/Manifest``, and this method
    /// overlays them on the baked registry via
    /// ``Lint/Configuration/lift(manifest:registry:inheriting:)`` so the runner
    /// lints `bundle` MINUS the consumer's `disabled` IDs. Absent the env var
    /// (every bare-bundle consumer, and local runs) the behaviour is unchanged.
    public static func run(bundle: [Lint.Rule.Configuration]) {
        let base: Lint.Configuration = Lint.Configuration { bundle }
        // Read the runtime selection overlay via the fail-loud ``Channel``. A
        // SET-but-unreadable selection manifest MUST NOT silently widen to the
        // full baked bundle (it would re-fire an EXCLUDED rule) — on a channel
        // error we emit to stderr and exit non-zero rather than lint a wrong
        // (wider) rule set with exit 0.
        let selection: Lint.Manifest?
        do throws(Lint.File.Single.Channel.Error) {
            selection = try Lint.File.Single.Channel.selection.read()
        } catch {
            failLoud("selection-manifest channel: \(error)")
        }
        guard let selection else {
            run(configuration: base)
            return
        }
        var registry: [Lint.Rule.ID: Lint.Rule] = [:]
        for entry in bundle {
            registry[entry.rule.id] = entry.rule
        }
        let overlaid: Lint.Configuration = Lint.Configuration.lift(
            manifest: selection,
            registry: registry,
            inheriting: base
        )
        run(configuration: overlaid)
    }

    /// Emit `message` to stderr and terminate the process with a non-zero exit.
    ///
    /// The fail-loud sink for a selection / parent ``Lint/File/Single/Channel``
    /// hard error: a set-but-unreadable manifest is a wrong-result-that-would-
    /// otherwise-exit-0 hazard, so the dispatched executable exits non-zero —
    /// the swift-linter CLI propagates that as its own non-zero exit. stdout
    /// stays the pure diagnostic stream; the error goes to stderr only.
    private static func failLoud(_ message: Swift.String) -> Never {
        Lint.Reporter.Text.emit(error: message, to: Terminal.Stream.stderr.write)
        Process.exit(1)
    }

    /// Run the linter with a complete configuration.
    public static func run(configuration: Lint.Configuration) {
        let arguments = Swift.CommandLine.arguments
        let pathStrings: [Swift.String] = arguments.count >= 2
            ? [Swift.String](arguments.dropFirst())
            : ["."]

        let consumerPaths: [File_System.File.Path]
        do throws(Paths.Path.Error) {
            consumerPaths = try pathStrings.map { (raw: Swift.String) throws(Paths.Path.Error) in
                try File_System.File.Path(raw)
            }
        } catch {
            print("[Lint] error: invalid path argument: \(error)")
            return
        }
        do throws(Lint.Run.Error) {
            let outcome: Lint.Run.Outcome = try Lint.Run.run(
                paths: consumerPaths,
                configuration: configuration,
                capturing: .all
            )
            Lint.Reporter.Text.emit(findings: outcome.findings, to: Terminal.Stream.stdout.write)
            // Always-on run summary to STDERR — stdout stays the pure diagnostic
            // stream. This is the shared terminal both the prebuilt runner
            // (`run(bundle:)`) and the eval-compiled executable
            // (`run(dependencies:)`) funnel through, so one emission covers both
            // paths. `effective` reflects the rule set AFTER bundle composition
            // and any runtime overlay/exclusions — i.e. what actually ran.
            let package: Swift.String = consumerPaths.first?.components.last?.string ?? "."
            Lint.Reporter.Text.emit(
                summaryFor: package,
                activeRules: configuration.rules.effective.entries.count,
                excludedRules: configuration.rules.effective.disabled.count,
                filesLinted: outcome.filesLinted,
                violations: outcome.findings.count,
                to: Terminal.Stream.stderr.write
            )
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
    ///
    /// Carries `Package.Dependency` from swift-spm-standard directly
    /// — the previous `Lint.Dependency` wrapper was retired with the
    /// v0.4 typed-Source-variants change in swift-spm-standard, which
    /// promoted `.path(String)` / `.url(String, ...)` to
    /// `.path(Paths.Path)` / `.url(URI, ...)`. The wrapper carried no
    /// further value once L2 was typed.
    public static func run(
        dependencies: [Package.Dependency],
        @Array<Lint.Rule.Configuration>.Builder rules: () -> [Lint.Rule.Configuration]
    ) {
        _ = dependencies
        let collected: [Lint.Rule.Configuration] = rules()
        var registry: [Lint.Rule.ID: Lint.Rule] = [:]
        for entry in collected {
            registry[entry.rule.id] = entry.rule
        }
        // Read the folded parent chain via the fail-loud ``Channel``. A
        // SET-but-unreadable parent manifest MUST NOT silently drop the
        // parent's rules — on a channel error we fail loud rather than lint a
        // silently-narrowed rule set with exit 0.
        let parent: Lint.Configuration?
        do throws(Lint.File.Single.Channel.Error) {
            parent = try Lint.File.Single.configuration(parentOf: registry)
        } catch {
            failLoud("parent-manifest channel: \(error)")
        }
        let configuration = Lint.Configuration(inheriting: parent) { collected }
        run(configuration: configuration)
    }
}
