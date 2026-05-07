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
    public static func run(
        paths: [File.Path],
        configuration: Lint.Configuration
    ) throws(Error) -> [Lint.Finding] {
        // (rule-instance, per-rule path filter) pairs. The filter
        // travels alongside the instantiated rule so the per-source
        // gate can read it without re-resolving the configuration.
        // Fully-qualified `Linter_Primitives.Path.Filter` because
        // `Path` is also declared in `Paths` (transitive via
        // `File_System`); both are visible here.
        let activeEntries: [(rule: any Lint.Rule.`Protocol`, paths: Linter_Primitives.Path.Filter?)] =
            configuration.effectiveRules().map { entry in
                let resolvedSeverity = entry.severity ?? entry.rule.defaultSeverity
                return (entry.rule.init(severity: resolvedSeverity), entry.paths)
            }
        var manager = Source.Manager()
        var findings: [Lint.Finding] = []
        for root in paths {
            let sourcePaths = Lint.Source.Walker.swiftSourcePaths(under: root)
            for sourcePath in sourcePaths {
                let parsed = try parsedSource(root: root, relativePath: sourcePath, manager: &manager)
                for (rule, filter) in activeEntries {
                    // Per-rule path filter — prefix-match per
                    // Path.Filter.matches(sourcePath:). A nil filter
                    // (entry has no `paths:` constraint) admits every
                    // sourcePath; a non-nil filter discriminates per
                    // its included/excluded prefix lists.
                    if let filter, !filter.matches(sourcePath: sourcePath) {
                        continue
                    }
                    findings.append(contentsOf: rule.findings(in: parsed))
                }
            }
        }
        return findings
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
        manager: inout Source.Manager
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
        let text = Swift.String(decoding: bytes, as: UTF8.self)
        let id = manager.register(fileID: absoluteString, filePath: absoluteString, content: bytes)
        let sourceFile = manager.file(for: id)
        let tree = Parser.parse(source: text)
        let converter = SourceLocationConverter(fileName: absoluteString, tree: tree)
        return Lint.Source.Parsed(file: sourceFile, tree: tree, converter: converter)
    }
}
