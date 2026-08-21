public import File_System
internal import Linter_Primitives
import SwiftParser
import SwiftSyntax

extension Lint {

    public enum Run {}
}

extension Lint.Run {

    public static func run(
        paths: [File.Path],
        configuration: Lint.Configuration
    ) throws(Error) -> [Lint.Finding] {
        let outcome = try run(paths: paths, capturing: .all, configuration: configuration)
        return outcome.findings
    }

    public static func run(
        paths: [File.Path],
        capturing capture: Capture,
        configuration: Lint.Configuration
    ) throws(Error) -> Outcome {

        let effective = configuration.rules.effective.entries
        var manager = Source.Manager()
        var findings: [Lint.Finding] = []
        var suppressed: [Lint.Finding] = []
        var filesLinted = 0

        let declaredTypeNames = Self.runDeclaredTypeNames(under: paths)
        for root in paths {
            let sourcePaths = Lint.Source.Walker.paths(under: root)
            for sourcePath in sourcePaths {
                let parsed = try parsedSource(
                    root: root,
                    relativePath: sourcePath,
                    manager: &manager,
                    declaredTypeNames: declaredTypeNames
                )
                filesLinted += 1
                let suppression = Lint.Suppression.scan(
                    tree: parsed.tree,
                    converter: parsed.converter
                )
                for entry in effective {
                    let severity = entry.severity ?? entry.rule.severity.default
                    let candidates = entry.rule.findings(parsed, severity)
                    for record in candidates {
                        let ruleID = Lint.Rule.ID(_unchecked: record.identifier)

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

    fileprivate static func parsedSource(
        root: File.Path,
        relativePath: Lint.Source.Path,
        manager: inout Source.Manager,
        declaredTypeNames: Swift.Set<Swift.String>
    ) throws(Error) -> Lint.Source.Parsed {
        let absoluteString: Swift.String
        let filePath: File.Path
        if relativePath.underlying.isEmpty {
            absoluteString = root.description
            filePath = root
        } else {

            let relative: File.Path
            do throws(Paths.Path.Error) {
                relative = try File.Path(relativePath.underlying)
            } catch {

                throw .fileNotReadable(path: root)
            }
            filePath = root.appending(relative)
            absoluteString = filePath.description
        }
        let file = File(filePath)
        let bytes: [Byte]
        do throws(Either<File.System.Read.Full.Error, Never>) {
            bytes = try file.read.full { (span: Swift.Span<Byte>) in
                var copy: [Byte] = []
                copy.reserveCapacity(span.count)
                span.indices.forEach { copy.append(span[$0]) }
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
            converter: converter,
            declaredTypeNames: declaredTypeNames
        )
    }

    fileprivate static func runDeclaredTypeNames(
        under paths: [File.Path]
    ) -> Swift.Set<Swift.String> {
        var names: Swift.Set<Swift.String> = []
        for root in paths {
            for sourcePath in Lint.Source.Walker.paths(under: root) {
                let filePath: File.Path
                if sourcePath.underlying.isEmpty {
                    filePath = root
                } else {
                    let relative: File.Path
                    do throws(File.Path.Error) {
                        relative = try File.Path(sourcePath.underlying)
                    } catch {
                        continue
                    }
                    filePath = root.appending(relative)
                }
                let file = File(filePath)
                let bytes: [Byte]
                do throws(Either<File.System.Read.Full.Error, Never>) {
                    bytes = try file.read.full { (span: Swift.Span<Byte>) in
                        var copy: [Byte] = []
                        copy.reserveCapacity(span.count)
                        span.indices.forEach { copy.append(span[$0]) }
                        return copy
                    }
                } catch {
                    continue
                }
                guard let text = Swift.String(validating: bytes, as: UTF8.self) else { continue }
                let tree = Parser.parse(source: text)
                names.formUnion(Lint.Brand.topLevelTypeNames(in: tree))
            }
        }
        return names
    }
}
