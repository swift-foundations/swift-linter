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

public import File_System
internal import Linter_Primitives
import SwiftParser
import SwiftSyntax

extension Lint {
    /// Applies the canonical fixes rules declare, in place.
    ///
    /// The measured motivation: the dominant remaining lint classes across
    /// the ecosystem are syntax-directed and their rules already specify
    /// exactly one canonical fix. Applying those by hand, per package, is
    /// the most expensive way to spend attention on the least ambiguous
    /// work there is. A rule that can state its fix as a whole-file rewrite
    /// states it once, in the rule, and the engine applies it everywhere.
    ///
    /// ## What this mode will and will not do
    ///
    /// Only rules carrying a non-`nil` ``Lint/Rule/fix`` participate. Every
    /// other rule is inert here — its findings are neither applied nor
    /// reported by this mode. So a fix run is never a lint run, and a fix
    /// run that changes nothing is never evidence that a tree is clean.
    ///
    /// A rewrite is applied only when the rewritten text **re-parses
    /// without new syntax errors**. A rewriter that produces something the
    /// parser rejects is a defect in that rewriter, and the engine's job is
    /// to refuse the output rather than write a broken file over a working
    /// one. The refusal is reported, not swallowed.
    ///
    /// Compilation is emphatically NOT checked here: the engine parses, it
    /// does not typecheck. That is why the applying caller — `workspace lint
    /// --fix` — builds afterwards, and why a fix commit's evidence is a
    /// green build rather than a clean fix run.
    ///
    /// ## Ordering
    ///
    /// Within one file the engine applies each participating rule in
    /// configuration order, re-parsing between rules so each rewriter sees
    /// the previous rewriter's output rather than the original text. Rules
    /// therefore compose without having to know about each other, and a
    /// rule never rewrites a node another rule has already replaced.
    public enum Fix {}
}

extension Lint.Fix {
    /// Applies every participating rule's canonical fix under `paths`.
    ///
    /// - Parameters:
    ///   - paths: Run roots, as passed to ``Lint/Run/run(paths:configuration:)``.
    ///   - configuration: The same configuration a lint run would use; only
    ///     its effective entries whose rule declares a fix participate.
    ///   - mode: Whether to write the rewritten files or only compute them.
    /// - Returns: One ``Change`` per file the run rewrote, plus the counts
    ///   needed to report that the run measured something.
    public static func apply(
        paths: [File.Path],
        configuration: Lint.Configuration,
        mode: Mode
    ) throws(Lint.Run.Error) -> Outcome {
        let fixable: [(id: Lint.Rule.ID, fix: @Sendable (borrowing Lint.Source.Parsed) -> Swift.String?)] =
            configuration.rules.effective.entries.compactMap { entry in
                guard let fix = entry.rule.fix else { return nil }
                return (id: entry.rule.id, fix: fix)
            }
        var manager = Source.Manager()
        var changes: [Change] = []
        var refusals: [Refusal] = []
        var filesScanned = 0
        guard !fixable.isEmpty else {
            return Outcome(changes: [], refusals: [], filesScanned: 0, fixableRules: 0)
        }
        for root in paths {
            for sourcePath in Lint.Source.Walker.paths(under: root) {
                let filePath = try Self.resolve(root: root, relativePath: sourcePath)
                let original = try Self.read(filePath)
                filesScanned += 1
                var current = original
                var applied: [Lint.Rule.ID] = []
                for candidate in fixable {
                    let parsed = Self.parse(
                        text: current,
                        filePath: filePath,
                        relativePath: sourcePath,
                        manager: &manager
                    )
                    // A file that has deliberately suppressed this rule
                    // anywhere is not a file this rule may rewrite. The
                    // suppression is line-scoped and the rewrite is
                    // whole-file, so there is no way to honour one inside
                    // the other — and the direction to be wrong in is
                    // obvious. Every `swift-linter:disable` in the tree
                    // carries a REASON stating why the canonical fix is
                    // wrong THERE, which is precisely the judgment this
                    // mode must not overrule. The file keeps its other
                    // rules' fixes; only the suppressed rule steps back.
                    let suppression = Lint.Suppression.scan(
                        tree: parsed.tree,
                        converter: parsed.converter
                    )
                    guard !suppression.entries.contains(where: { $0.rule == candidate.id }) else {
                        continue
                    }
                    guard let rewritten = candidate.fix(parsed), rewritten != current else {
                        continue
                    }
                    // A rewriter that emits unparseable text is a defect in
                    // that rewriter. Refuse its output rather than write it:
                    // the whole value of this mode is that it cannot be the
                    // reason a tree stops building.
                    guard Self.parses(rewritten) else {
                        refusals.append(
                            Refusal(path: filePath, rule: candidate.id)
                        )
                        continue
                    }
                    current = rewritten
                    applied.append(candidate.id)
                }
                guard current != original else { continue }
                if mode == .apply {
                    try Self.write(current, to: filePath)
                }
                changes.append(
                    Change(
                        path: filePath,
                        rules: applied,
                        original: original,
                        fixed: current
                    )
                )
            }
        }
        return Outcome(
            changes: changes,
            refusals: refusals,
            filesScanned: filesScanned,
            fixableRules: fixable.count
        )
    }
}

extension Lint.Fix {
    /// Joins a walker-emitted relative path onto its run root.
    ///
    /// Mirrors the resolution in ``Lint/Run`` — an empty relative path is
    /// the walker's single-file-root mode, where the root IS the file.
    fileprivate static func resolve(
        root: File.Path,
        relativePath: Lint.Source.Path
    ) throws(Lint.Run.Error) -> File.Path {
        guard !relativePath.underlying.isEmpty else { return root }
        let relative: File.Path
        do throws(Paths.Path.Error) {
            relative = try File.Path(relativePath.underlying)
        } catch {
            throw .fileNotReadable(path: root)
        }
        return root.appending(relative)
    }

    fileprivate static func read(_ path: File.Path) throws(Lint.Run.Error) -> Swift.String {
        let bytes: [Byte]
        do throws(Either<File.System.Read.Full.Error, Never>) {
            bytes = try File(path).read.full { (span: Swift.Span<Byte>) in
                var copy: [Byte] = []
                copy.reserveCapacity(span.count)
                span.indices.forEach { copy.append(span[$0]) }
                return copy
            }
        } catch {
            throw .fileNotReadable(path: path)
        }
        guard let text = Swift.String(validating: bytes, as: UTF8.self) else {
            throw .nonUTF8(path: path)
        }
        return text
    }

    fileprivate static func write(_ text: Swift.String, to path: File.Path) throws(Lint.Run.Error) {
        do throws(File.System.Write.Atomic.Error) {
            try File(path).write.atomic(text)
        } catch {
            // The typed run error vocabulary has one path-shaped failure
            // per direction of travel; a write failure surfaces as the
            // unreadable-file case rather than growing the enum for a
            // mode that has exactly one write site.
            throw .fileNotReadable(path: path)
        }
    }

    /// Parses `text` into the bundle rule fixes consume.
    ///
    /// `declaredTypeNames` is deliberately empty: the brand pre-pass exists
    /// so a boundary rule can self-suppress at a brand owner's own surface,
    /// and a rewriter that rewrites on brand ownership would be making a
    /// cross-file judgment inside a whole-file rewrite. No fix needs it, and
    /// a fix that thinks it does should not be a whole-file rewrite.
    fileprivate static func parse(
        text: Swift.String,
        filePath: File.Path,
        relativePath: Lint.Source.Path,
        manager: inout Source.Manager
    ) -> Lint.Source.Parsed {
        let name = filePath.description
        let tree = Parser.parse(source: text)
        let id = manager.register(fileID: name, filePath: name, content: [Byte](text.utf8))
        return Lint.Source.Parsed(
            file: manager.file(for: id),
            path: relativePath,
            tree: tree,
            converter: SourceLocationConverter(fileName: name, tree: tree)
        )
    }

    /// Whether `text` parses with no syntax errors.
    ///
    /// SwiftParser always returns a tree — it recovers rather than failing —
    /// so "did it parse" is a question about the presence of error nodes,
    /// not about a thrown error.
    fileprivate static func parses(_ text: Swift.String) -> Swift.Bool {
        !Parser.parse(source: text).hasError
    }
}
