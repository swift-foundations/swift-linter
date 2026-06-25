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

import SwiftSyntax
import SwiftParser
internal import Cardinal_Primitives
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
    /// path: `entry.rule.init(severity: entry.severity ?? entry.rule.severity.default)`.
    /// No string-name lookup; identity flows through `.self`.
    ///
    /// ## Composition order (per-rule scope)
    ///
    /// Two scoping mechanisms compose at distinct stages:
    ///
    /// 1. ``Lint/Rule/Configuration/Mode/disabled`` short-circuits at
    ///    ``Lint/Configuration/Rules/effective`` — disabled entries
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
    public static func run(
        paths: [File.Path],
        configuration: Lint.Configuration
    ) throws(Error) -> [Lint.Finding] {
        let outcome = try run(paths: paths, capturing: .all, configuration: configuration)
        return outcome.findings
    }

    /// Outcome-returning variant; the ``Capture`` value controls which
    /// streams (findings, suppressed, or both) the engine populates.
    ///
    /// Per-finding disable mechanism (decision 2026-05-11, hybrid
    /// line-comment + config-file): for each parsed source file the
    /// engine first builds a ``Lint/Suppression`` map via
    /// ``Lint/Suppression/scan(tree:converter:)``, then consults the
    /// map for each finding before deciding which stream(s) it joins.
    /// The rule-wide-disable axis is honored at
    /// ``Lint/Configuration/Rules/effective`` — rule IDs in
    /// ``Lint/Configuration/Rules/disabled`` never reach this loop.
    ///
    /// `configuration` sits LAST (after the `capturing:` modifier) so the
    /// configuration-bearing parameter is at the last non-closure position per
    /// `[API-IMPL-014]` — `paths` is the primary domain input; the run is tuned
    /// by `capturing:` and `configuration:`.
    public static func run(
        paths: [File.Path],
        capturing capture: Capture,
        configuration: Lint.Configuration
    ) throws(Error) -> Outcome {
        // Witness-shape engine. Each effective entry stores a `Lint.Rule`
        // witness with any per-rule path filter already folded in via
        // `Lint.Rule.filtered(toPaths:)` at configuration time. The
        // engine simply resolves severity and invokes the witness's
        // findings closure — no existential dispatch, no `init(severity:)`
        // factory hop, no per-entry filter branch.
        let effective = configuration.rules.effective.entries
        var manager = Source.Manager()
        var findings: [Lint.Finding] = []
        var suppressed: [Lint.Finding] = []
        var filesLinted: Lint.Source.Count = .zero
        for root in paths {
            let sourcePaths = Lint.Source.Walker.paths(under: root)
            for sourcePath in sourcePaths {
                let parsed = try parsedSource(root: root, relativePath: sourcePath, manager: &manager)
                filesLinted += .one
                let suppression = Lint.Suppression.scan(
                    tree: parsed.tree,
                    converter: parsed.converter
                )
                for entry in effective {
                    let severity = entry.severity ?? entry.rule.severity.default
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
                        if suppression.suppresses(line: record.location.line, rule: ruleID) {
                            if capture != .findings {
                                suppressed.append(finding)
                            }
                            continue
                        }
                        if capture != .suppressed {
                            findings.append(finding)
                        }
                    }
                }
            }
        }
        return Outcome(findings: findings, suppressed: suppressed, filesLinted: filesLinted)
    }

    /// Reads, parses, and registers the source file at
    /// `root + relativePath` for the engine.
    ///
    /// `root` is the run-root passed to ``run(paths:configuration:)``
    /// (typed `File.Path`); `relativePath` is the walker-emitted
    /// ``Lint/Source/Path`` (run-root-relative). When `relativePath`
    /// is empty the walker is in single-file-root mode and `root`
    /// itself is the file. Otherwise the resolver joins via
    /// ``File/Path/appending(_:)`` — separator semantics and
    /// component validation come from the typed primitive (see
    /// ``Manifest/Executable/Materializer/resolve(_:relativeTo:)``
    /// for the same pattern).
    fileprivate static func parsedSource(
        root: File.Path,
        relativePath: Lint.Source.Path,
        manager: inout Source.Manager
    ) throws(Error) -> Lint.Source.Parsed {
        let absoluteString: Swift.String
        let filePath: File.Path
        if relativePath.underlying.isEmpty {
            absoluteString = root.description
            filePath = root
        } else {
            // F-A1.3: typed `File.Path` appending replaces the prior
            // `rootString + separator + relativePath.underlying`
            // manual separator math. `relative` is constructed first
            // so a malformed walker-emitted path surfaces a
            // `Path.Error` rather than a downstream open-file failure.
            let relative: File.Path
            do throws(Paths.Path.Error) {
                relative = try File.Path(relativePath.underlying)
            } catch {
                // Walker-emitted relative path failed `File.Path`
                // validation — the closest meaningful path on the
                // typed error is `root` (the parent directory the
                // file was discovered under).
                throw .fileNotReadable(path: root)
            }
            filePath = root.appending(relative)
            absoluteString = filePath.description
        }
        let file = File(filePath)
        let bytes: [Byte]
        do throws(File.System.Read.Full.Error) {
            bytes = try file.read.full { (span: Swift.Span<Byte>) in
                var copy: [Byte] = []
                copy.reserveCapacity(span.count)
                for i in 0..<span.count {
                    copy.append(span[i])
                }
                return copy
            }
        } catch {
            throw .fileNotReadable(path: filePath)
        }
        guard let text = Swift.String(validating: bytes, as: UTF8.self) else {
            throw .nonUTF8(path: filePath)
        }
        let id = manager.register(fileID: absoluteString, filePath: absoluteString, content: bytes)
        let sourceFile = manager.file(for: id)
        let tree = Parser.parse(source: text)
        let converter = SourceLocationConverter(fileName: absoluteString, tree: tree)
        return Lint.Source.Parsed(
            file: sourceFile,
            path: relativePath,
            tree: tree,
            converter: converter
        )
    }
}
