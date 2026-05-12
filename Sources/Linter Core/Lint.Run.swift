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

public import SwiftSyntax
public import SwiftParser
public import File_System
internal import Linter_Primitives

/// Run the linter against one or more paths.
///
/// File reads compose `swift-file-system`'s `File.read.full { span in … }`
/// (Foundation-clean). The linter parses each file once via SwiftParser
/// and runs every activated rule against the same tree (per the brief's
/// memory + perf constraint).
extension Lint {
    public enum Run {}
}

extension Lint.Run {
    /// Run the linter against `paths` using `configuration`'s effective
    /// (parent-merged, override-applied, disabled-dropped) rule set.
    ///
    /// Each effective entry instantiates its rule via the typed metatype
    /// path: `entry.rule.init(severity: entry.severity ?? entry.rule.defaultSeverity)`.
    /// No string-name lookup; identity flows through `.self`.
    ///
    /// ## Composition order (per-rule scope)
    ///
    /// Two scoping mechanisms compose at distinct stages:
    ///
    /// 1. ``Lint/Rule/Configuration/Mode/disabled`` short-circuits at
    ///    ``Lint/Configuration/effectiveRules()`` — disabled entries
    ///    never reach this loop.
    /// 2. The per-rule ``Lint/Rule/Configuration/paths`` filter
    ///    (``Lint/Path/Filter``) applies HERE, per (rule, source-path)
    ///    pair, AFTER the disabled-drop and rule instantiation. A `nil`
    ///    filter (no path scope on the entry) admits every path; a
    ///    non-`nil` filter applies prefix-match semantics per
    ///    ``Lint/Path/Filter/matches(sourcePath:)``.
    ///
    /// Stage (1) decides which rules participate; stage (2) decides
    /// which (rule, file) pairs the engine actually invokes.
    ///
    /// `paths` are typed `File.Path` values — input boundary lives at
    /// the CLI (where `ArgumentParser` strings cross `try File.Path(_:)`).
    /// The walker emits run-root-relative ``Lint/Source/Path`` values;
    /// the filter, the rule invocation, and the parsed-source resolver
    /// all read typed.
    ///
    /// ## Working set
    ///
    /// The run instantiates a single `Source.Manager` and threads it
    /// through every parsed-source resolution. The manager retains
    /// each registered file's bytes for the duration of the run so
    /// that rules MAY perform cross-file analysis against any prior
    /// parsed source. The working-set memory cost is therefore
    /// proportional to the total source-tree size rather than to the
    /// largest single file.
    ///
    /// For consumer trees in the typical SwiftPM-package range
    /// (single-digit megabytes of source), the retain-all shape is
    /// negligible. Consumers running against very large trees
    /// (tens-of-thousands of files; corporate monorepos; aggregated
    /// dependency-graphs) should expect proportional memory residency
    /// and MAY chunk runs by sub-tree to bound the working set.
    ///
    /// ## Brand-type admission
    ///
    /// Recognizer-class rules consult the run's brand-newtype set
    /// (`raw value access`, `chain`, `bitpattern`, `int parameter`).
    /// The set is sourced from the configuration's
    /// ``Lint/Configuration/effectiveBrands()`` — walking the parent
    /// chain once at run start. The engine threads the result onto
    /// every parsed source the walker emits so recognizer-class
    /// rules can admit same-package access without firing —
    /// preserving strict-superset for cross-package consumers.
    ///
    /// Shape γ consumers declare brands at the call site:
    /// `Lint.run(dependencies: …, brands: ["Ordinal"]) { … }`.
    ///
    /// See
    /// `swift-foundations/swift-linter-rules/Research/numerics-rule-recognizer-2026-05-12.md`
    /// for the recognizer-class rule prose. The all-Swift kwarg shape
    /// supersedes the prior `.swift-linter.json` per-file discovery
    /// model — see `project_linter_config_all_swift.md` for the
    /// convention.
    public static func run(
        paths: [File.Path],
        configuration: Lint.Configuration
    ) throws(Error) -> [Lint.Finding] {
        let outcome = try runCapturingSuppressed(paths: paths, configuration: configuration)
        return outcome.findings
    }

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
        /// per-source ``Lint/Suppression`` consultation. Each finding
        /// pairs the rule-emitted ``Diagnostic_Primitives/Diagnostic/Record``
        /// with the effective ``Lint/Visibility`` of its enclosing decl.
        public let findings: [Lint.Finding]

        /// Findings the engine elided because a `swift-linter:disable`
        /// directive matched. Recorded for observability; never the
        /// engine's exit-policy signal. Visibility is computed for
        /// suppressed findings too — empirical follow-ups can segment
        /// the suppressed stream by visibility the same way as the
        /// surfaced one.
        public let suppressed: [Lint.Finding]

        @inlinable
        public init(
            findings: [Lint.Finding] = [],
            suppressed: [Lint.Finding] = []
        ) {
            self.findings = findings
            self.suppressed = suppressed
        }
    }

    /// Variant that returns the suppressed-finding observability
    /// stream alongside the engine's surfaced findings.
    ///
    /// Per-finding disable mechanism (decision 2026-05-11, hybrid
    /// line-comment + config-file): for each parsed source file the
    /// engine first builds a ``Lint/Suppression`` map via
    /// ``Lint/Suppression/scan(tree:converter:)``, then consults the
    /// map for each finding before adding it to the return value. The
    /// rule-wide-disable axis is honored at
    /// ``Lint/Configuration/effectiveRules()`` — rule IDs in
    /// ``Lint/Configuration/disabledRuleIDs`` never reach this loop.
    public static func runCapturingSuppressed(
        paths: [File.Path],
        configuration: Lint.Configuration
    ) throws(Error) -> Outcome {
        // Witness-shape engine. Each effective entry stores a `Lint.Rule`
        // witness with any per-rule path filter already folded in via
        // `Lint.Rule.filtered(toPaths:)` at configuration time. The
        // engine simply resolves severity and invokes the witness's
        // findings closure — no existential dispatch, no `init(severity:)`
        // factory hop, no per-entry filter branch.
        let effective = configuration.effectiveRules()
        let brandTypes = configuration.effectiveBrands()
        var manager = Source.Manager()
        var findings: [Lint.Finding] = []
        var suppressed: [Lint.Finding] = []
        for root in paths {
            let sourcePaths = Lint.Source.Walker.swiftSourcePaths(under: root)
            for sourcePath in sourcePaths {
                let parsed = try parsedSource(root: root, relativePath: sourcePath, manager: &manager, brandTypes: brandTypes)
                let suppression = Lint.Suppression.scan(
                    tree: parsed.tree,
                    converter: parsed.converter
                )
                for entry in effective {
                    let severity = entry.severity ?? entry.rule.defaultSeverity
                    let candidates = entry.rule.findings(parsed, severity)
                    for record in candidates {
                        let ruleID = Lint.Rule.ID(_unchecked: record.identifier)
                        // Visibility computation is post-rule: rules
                        // emit bare records (so their findings closure
                        // signatures stay stable), and the engine wraps
                        // each record into a `Lint.Finding` tagged with
                        // the effective visibility of the enclosing
                        // decl chain. The reverse-position walk lives
                        // in `Lint.Source.Parsed.visibility(at:)`.
                        let visibility = parsed.visibility(at: record.location)
                        let finding = Lint.Finding(
                            record: record,
                            visibility: visibility
                        )
                        if suppression.suppresses(line: record.location.line, ruleID: ruleID) {
                            suppressed.append(finding)
                            continue
                        }
                        findings.append(finding)
                    }
                }
            }
        }
        return Outcome(findings: findings, suppressed: suppressed)
    }

    /// Reads, parses, and registers the source file at
    /// `root + relativePath` for the engine.
    ///
    /// `root` is the run-root passed to ``run(paths:configuration:)``
    /// (typed `File.Path`); `relativePath` is the walker-emitted
    /// ``Lint/Source/Path`` (run-root-relative). When `relativePath`
    /// is empty the walker is in single-file-root mode and `root`
    /// itself is the file. Otherwise the resolver concatenates
    /// `root.description + "/" + relativePath.underlying` to obtain
    /// the absolute string for I/O. The concatenation is the typed
    /// boundary's mechanism — bare strings exist here, in the
    /// resolver body, and nowhere else in the engine.
    static func parsedSource(
        root: File.Path,
        relativePath: Lint.Source.Path,
        manager: inout Source.Manager,
        brandTypes: Swift.Set<Lint.Brand>
    ) throws(Error) -> Lint.Source.Parsed {
        let absoluteString: Swift.String
        let filePath: File.Path
        if relativePath.underlying.isEmpty {
            absoluteString = root.description
            filePath = root
        } else {
            let rootString = root.description
            let separator = rootString.hasSuffix("/") ? "" : "/"
            absoluteString = rootString + separator + relativePath.underlying
            do {
                filePath = try File.Path(absoluteString)
            } catch {
                throw .fileNotReadable(path: absoluteString)
            }
        }
        let file = File(filePath)
        let bytes: [UInt8]
        do {
            bytes = try file.read.full { (span: Span<UInt8>) in
                var copy: [UInt8] = []
                copy.reserveCapacity(span.count)
                for i in 0..<span.count {
                    copy.append(span[i])
                }
                return copy
            }
        } catch {
            throw .fileNotReadable(path: absoluteString)
        }
        guard let text = Swift.String(validating: bytes, as: UTF8.self) else {
            throw .nonUTF8(path: absoluteString)
        }
        let id = manager.register(fileID: absoluteString, filePath: absoluteString, content: bytes)
        let sourceFile = manager.file(for: id)
        let tree = Parser.parse(source: text)
        let converter = SourceLocationConverter(fileName: absoluteString, tree: tree)
        return Lint.Source.Parsed(
            file: sourceFile,
            path: relativePath,
            tree: tree,
            converter: converter,
            brandTypes: brandTypes
        )
    }
}
