public import File_System
internal import Linter_Primitives
import SwiftParser
import SwiftSyntax

extension Lint {

    public enum Fix {}
}

extension Lint.Fix {

    public static func apply(
        paths: [File.Path],
        targets: [File.Path],
        configuration: Lint.Configuration,
        excluding excludedRules: Set<Lint.Rule.ID> = [],
        mode: Mode,
        manifest: File.Path? = nil
    ) throws(Lint.Run.Error) -> Outcome {
        let fixable:
            [(id: Lint.Rule.ID, fix: @Sendable (borrowing Lint.Source.Parsed) -> Swift.String?)] =
                configuration.rules.effective.entries.compactMap { entry in
                    guard let fix = entry.rule.fix else { return nil }
                    return (id: entry.rule.id, fix: fix)
                }
        let excluded: [Lint.Rule.ID] =
            fixable
            .filter { excludedRules.contains($0.id) }
            .map(\.id)
        let participating = fixable.filter { !excludedRules.contains($0.id) }
        var manager = Source.Manager()
        var changes: [Change] = []
        var refusals: [Refusal] = []
        var plannedRules: [Lint.Rule.ID] = []
        var filesScanned = 0
        guard !fixable.isEmpty else {
            return Outcome(
                changes: [],
                excludedRules: [],
                plannedRules: [],
                refusals: [],
                filesScanned: 0,
                fixableRules: 0
            )
        }
        for root in paths {
            for sourcePath in Lint.Source.Walker.paths(under: root) {
                let filePath = try Self.resolve(root: root, relativePath: sourcePath)
                filesScanned += 1

                let isManifest = manifest == filePath
                guard targets.contains(where: { filePath.hasPrefix($0) }) || isManifest else {
                    continue
                }

                guard !Self.isFixtureScoped(filePath) else { continue }
                let original = try Self.read(filePath)
                var current = original
                var applied: [Lint.Rule.ID] = []
                for candidate in participating {
                    let parsed = Self.parse(
                        text: current,
                        filePath: filePath,
                        relativePath: sourcePath,
                        manager: &manager
                    )

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

                    guard Self.parses(rewritten) else {
                        refusals.append(
                            Refusal(path: filePath, rule: candidate.id, reason: .unparseable)
                        )
                        continue
                    }

                    guard !isManifest || Scope.Manifest.evaluates(rewritten) else {
                        refusals.append(
                            Refusal(
                                path: filePath,
                                rule: candidate.id,
                                reason: .manifestEvaluationFailed
                            )
                        )
                        continue
                    }
                    current = rewritten
                    applied.append(candidate.id)
                    if !plannedRules.contains(candidate.id) {
                        plannedRules.append(candidate.id)
                    }
                }
                guard current != original else { continue }
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
        let published: [File.Path]
        if mode == .apply, refusals.isEmpty {
            published = try Lint.Fix.Publisher.apply(changes)
        } else {
            published = []
        }
        return Outcome(
            changes: changes,
            excludedRules: excluded,
            plannedRules: plannedRules,
            published: published,
            refusals: refusals,
            filesScanned: filesScanned,
            fixableRules: fixable.count
        )
    }
}

extension Lint.Fix {

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

    internal static func isFixtureScoped(_ path: File.Path) -> Swift.Bool {
        var segments: [Swift.Substring] =
            path.description
            .split(separator: "/", omittingEmptySubsequences: true)

        guard !segments.isEmpty else { return false }
        segments.removeLast()
        return segments.contains { $0.lowercased() == "fixtures" }
    }

    internal static func read(_ path: File.Path) throws(Lint.Run.Error) -> Swift.String {
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

    internal static func parses(_ text: Swift.String) -> Swift.Bool {
        !Parser.parse(source: text).hasError
    }
}
