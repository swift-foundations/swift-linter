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
public import Linter_Core
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
/// the engine against them, and emits findings in the report format selected
/// by ``Lint/Reporter/Format/Channel``. Unset preserves text. Errors are
/// printed and the process exits non-zero.
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
        let base: Lint.Configuration = Self.Configuration { bundle }
        // Read the runtime selection overlay via the fail-loud ``Channel``. A
        // SET-but-unreadable selection manifest MUST NOT silently widen to the
        // full baked bundle (it would re-fire an EXCLUDED rule) — on a channel
        // error we emit to stderr and exit non-zero rather than lint a wrong
        // (wider) rule set with exit 0.
        let selection: Lint.Manifest?
        do throws(Self.File.Single.Channel.Error) {
            selection = try Self.File.Single.Channel.selection.read()
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
        let overlaid: Lint.Configuration = Self.Configuration.lift(
            manifest: selection,
            registry: registry,
            inheriting: base
        )
        run(configuration: overlaid)
    }

    /// Run the prebuilt standard runner with its full baked-bundle catalogue,
    /// selecting the bundle named on the ``Lint/Rule/Bundle/Baked/Channel``.
    ///
    /// The A4-gap runner entry point: the runner's `main.swift` bakes EVERY
    /// published standard bundle and passes them keyed by their
    /// ``Lint/Rule/Bundle/Baked`` token:
    ///
    /// ```swift
    /// Lint.run(bundles: [
    ///     .primitives: Lint.Rule.Bundle.primitives,
    ///     .standards: Lint.Rule.Bundle.standards,
    ///     .institute: Lint.Rule.Bundle.institute,
    /// ])
    /// ```
    ///
    /// The dispatcher exports the consumer's classifier-recognized bundle
    /// token on the channel before spawning; this method reads it and runs
    /// ``run(bundle:)`` with the matching baked set. Unset ⇒ `.primitives`
    /// (the sole bundle a pre-A4 dispatcher ever routed, so old dispatchers
    /// keep their exact behavior). Fail-loud on a SET-but-invalid token AND
    /// on a valid token absent from `bundles`: silently substituting a
    /// different bundle than the consumer selected would be a
    /// wrong-result-that-exits-0 hazard (mirrors the selection / parent /
    /// exit-policy channel discipline).
    public static func run(bundles: [Lint.Rule.Bundle.Baked: [Lint.Rule.Configuration]]) {
        let requested: Lint.Rule.Bundle.Baked
        do throws(Lint.Rule.Bundle.Baked.Channel.Error) {
            requested = try Lint.Rule.Bundle.Baked.Channel.read() ?? .primitives
        } catch {
            failLoud("bundle channel: \(error)")
        }
        guard let bundle: [Lint.Rule.Configuration] = bundles[requested] else {
            // swift-linter:disable:next raw value access
            // REASON: `Lint.Rule.Bundle.Baked` is a `String`-backed enum whose
            // raw value IS the channel's wire vocabulary; the diagnostic names
            // the wire token the dispatcher sent, not a Tagged payload.
            failLoud("bundle channel: this runner does not bake bundle '\(requested.rawValue)'")
        }
        run(bundle: bundle)
    }

    /// Emit `message` to stderr and terminate the process with a non-zero exit.
    ///
    /// The fail-loud sink for a dispatched-executable channel hard error. A
    /// set-but-invalid format, policy, selection, or parent value is a
    /// wrong-result-that-would-otherwise-exit-0 hazard, so the executable exits
    /// non-zero and the swift-linter CLI propagates that result. stdout stays
    /// the pure diagnostic stream; the error goes to stderr only.
    private static func failLoud(_ message: Swift.String) -> Never {
        Self.Reporter.Text.emit(error: message, to: Terminal.Stream.stderr.write)
        Process.exit(1)
    }

    /// Run the linter with a complete configuration.
    public static func run(configuration: Lint.Configuration) {
        let arguments = Swift.CommandLine.arguments
        let pathStrings: [Swift.String] =
            arguments.count >= 2
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
        // Fix mode (`SWIFT_LINTER_FIX`, exported by the swift-linter CLI's
        // `--fix` before dispatch) is checked BEFORE the lint run, because
        // it replaces it rather than modifying it: a fix run applies
        // rewriters and reports diffs, and reports no findings at all. The
        // channel is read at this same shared terminal both dispatch paths
        // funnel through, so one check covers the prebuilt runner and the
        // eval-compiled executable alike. SET-but-invalid fails loud — see
        // `Lint.Fix.Mode.Channel`, where the fallback hazards are the worst
        // on any channel here (silently linting instead of fixing, or
        // silently writing instead of previewing).
        let fixMode: Lint.Fix.Mode?
        do throws(Lint.Fix.Mode.Channel.Error) {
            fixMode = try Lint.Fix.Mode.Channel.read()
        } catch {
            failLoud("fix channel: \(error)")
        }
        if let fixMode {
            let targets: [File_System.File.Path]
            do throws(Lint.Fix.Scope.Channel.Error) {
                guard let supplied = try Lint.Fix.Scope.Channel.read() else {
                    failLoud(
                        "fix target-root channel is unset; target membership must be supplied by the package manifest"
                    )
                }
                targets = supplied
            } catch {
                failLoud("fix target-root channel: \(error)")
            }
            let exclusions: Set<Lint.Rule.ID>
            do throws(Lint.Fix.Exclusion.Channel.Error) {
                exclusions = try Lint.Fix.Exclusion.Channel.read() ?? []
            } catch {
                failLoud("fix exclusion channel: \(error)")
            }
            let manifest: File_System.File.Path?
            do throws(Lint.Fix.Scope.Manifest.Channel.Error) {
                manifest = try Lint.Fix.Scope.Manifest.Channel.read()
            } catch {
                failLoud("fix manifest channel: \(error)")
            }
            runFix(
                mode: fixMode,
                paths: consumerPaths,
                targets: targets,
                excluding: exclusions,
                configuration: configuration,
                manifest: manifest
            )
            return
        }
        let format: Lint.Reporter.Format
        do throws(Lint.Reporter.Format.Channel.Error) {
            format = try Lint.Reporter.Format.Channel.read()
        } catch {
            failLoud("output-format channel: \(error)")
        }
        do throws(Self.Run.Error) {
            let outcome: Lint.Run.Outcome = try Self.Run.run(
                paths: consumerPaths,
                capturing: .all,
                configuration: configuration
            )
            format.emit(findings: outcome.findings, to: Terminal.Stream.stdout.write)
            // Always-on run summary to STDERR — stdout stays the pure diagnostic
            // stream. This is the shared terminal both the prebuilt runner
            // (`run(bundle:)`) and the eval-compiled executable
            // (`run(dependencies:)`) funnel through, so one emission covers both
            // paths. `effective` reflects the rule set AFTER bundle composition
            // and any runtime overlay/exclusions — i.e. what actually ran.
            let package: Swift.String = consumerPaths.first?.components.last?.string ?? "."
            // The run-summary counts are bare `Int` display values (see
            // `Lint.Reporter.Text.Summary.line` — typing them would pull a
            // cardinal dependency tree into the engine for no semantic gain).
            // `.count` flows straight through.
            Self.Reporter.Text.emit(
                summaryFor: package,
                activeRules: configuration.rules.effective.entries.count,
                excludedRules: configuration.rules.effective.disabled.count,
                filesLinted: outcome.filesLinted,
                violations: outcome.violations.count,
                to: Terminal.Stream.stderr.write
            )
            // Exit-policy channel (`SWIFT_LINTER_EXIT_POLICY`, exported by the
            // swift-linter CLI before dispatch): this is the shared terminal
            // BOTH the prebuilt standard runner (`run(bundle:)`) and the
            // eval-compiled executable (`run(dependencies:rules:)`) funnel
            // through, so one check gives both dispatch paths strict-exit
            // parity with the CLI's in-process fallback. Unset ⇒ advisory
            // (local-run default, exit 0). SET-but-invalid fails loud — a
            // silently-weakened exit policy would be a wrong-result-that-
            // exits-0 hazard (same discipline as the selection / parent
            // channels).
            let policy: Lint.Run.Policy?
            do throws(Lint.Run.Policy.Channel.Error) {
                policy = try Lint.Run.Policy.Channel.read()
            } catch {
                failLoud("exit-policy channel: \(error)")
            }
            if policy?.fails(for: outcome.findings) == true {
                Process.exit(1)
            }
        } catch {
            print("[Lint] error: \(error)")
        }
    }

    /// Applies (or previews) the canonical fixes rules declare, and reports
    /// what it did.
    ///
    /// Diffs go to stdout — they are this mode's diagnostic stream, the way
    /// findings are a lint run's. The summary and every refusal go to
    /// stderr, matching the lint run's split, so a caller may pipe the
    /// diffs into `git apply` or a pager without a summary line landing in
    /// the middle of them.
    ///
    /// A refused rewrite exits non-zero regardless of mode. It means a
    /// rewriter emitted text the parser rejects, and a fix run that reported
    /// that on stderr and exited zero would let a broken rewriter keep
    /// shipping behind a green result.
    private static func runFix(
        mode: Lint.Fix.Mode,
        paths: [File_System.File.Path],
        targets: [File_System.File.Path],
        excluding exclusions: Set<Lint.Rule.ID>,
        configuration: Lint.Configuration,
        manifest: File_System.File.Path? = nil
    ) {
        let outcome: Lint.Fix.Outcome
        do throws(Self.Run.Error) {
            outcome = try Lint.Fix.apply(
                paths: paths,
                targets: targets,
                configuration: configuration,
                excluding: exclusions,
                mode: mode,
                manifest: manifest
            )
        } catch {
            failLoud("fix: \(error)")
        }
        for change in outcome.changes {
            Self.Reporter.Text.emit(text: change.diff, to: Terminal.Stream.stdout.write)
        }
        for rule in outcome.excludedRules {
            Self.Reporter.Text.emit(
                text: "[swift-linter] fix: withheld rule '\(rule)'\n",
                to: Terminal.Stream.stderr.write
            )
        }
        for rule in outcome.plannedRules {
            let verb: Swift.String =
                mode == .apply && outcome.refusals.isEmpty
                ? "applied"
                : "would apply"
            Self.Reporter.Text.emit(
                text: "[swift-linter] fix: \(verb) rule '\(rule)'\n",
                to: Terminal.Stream.stderr.write
            )
        }
        for refusal in outcome.refusals {
            Self.Reporter.Text.emit(
                error: "fix for rule '\(refusal.rule)' \(refusal.reason.summary) for "
                    + "\(refusal.path); the complete fix plan was not published",
                to: Terminal.Stream.stderr.write
            )
        }
        // The always-on run summary is emitted for a fix run too, in the
        // identical shape. A caller adjudicating whether a run measured
        // anything — Workspace does, for every package in a sweep — must not
        // have to know which mode produced the line, and a fix run that
        // printed no summary would be indistinguishable from one that loaded
        // no rules and silently did nothing. `violations` is the number of
        // files rewritten: in this mode that is what the run found.
        let reportedChanges: Swift.Int =
            mode == .apply ? outcome.published.count : outcome.paths.count
        let package: Swift.String = paths.first?.components.last?.string ?? "."
        Self.Reporter.Text.emit(
            summaryFor: package,
            activeRules: configuration.rules.effective.entries.count,
            excludedRules: configuration.rules.effective.disabled.count,
            filesLinted: outcome.filesScanned,
            violations: reportedChanges,
            to: Terminal.Stream.stderr.write
        )
        let verb: Swift.String = (mode == .apply) ? "rewrote" : "would rewrite"
        Self.Reporter.Text.emit(
            text: "[swift-linter] fix: \(verb) \(reportedChanges) of "
                + "\(outcome.filesScanned) files · \(outcome.fixableRules) "
                + "fix-capable rules active\n",
            to: Terminal.Stream.stderr.write
        )
        if !outcome.refusals.isEmpty {
            Process.exit(1)
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
    /// v0.4 typed-Source-variants change in swift-spm-standard. URL-form
    /// dependencies carry ``RFC_3986/URI`` while path-form dependencies keep
    /// SwiftPM's path string; operational path validation and resolution stay
    /// in the linter foundation. The wrapper carried no further value once the
    /// source variants themselves became typed.
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
        do throws(Self.File.Single.Channel.Error) {
            parent = try Self.File.Single.configuration(parentOf: registry)
        } catch {
            failLoud("parent-manifest channel: \(error)")
        }
        let configuration = Self.Configuration(inheriting: parent) { collected }
        run(configuration: configuration)
    }
}
