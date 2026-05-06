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
    public static func run(
        paths: [Swift.String],
        configuration: Lint.Configuration,
        rules: [any Lint.Rule.`Protocol`]
    ) throws(Error) -> [Lint.Finding] {
        let activatedRules = rules.filter { configuration.isActivated(type(of: $0).id) }
        var manager = Source.Manager()
        var findings: [Lint.Finding] = []
        for path in paths {
            let sourcePaths = Lint.Source.Walker.swiftSourcePaths(under: path)
            for sourcePath in sourcePaths {
                let parsed = try parsedSource(at: sourcePath, manager: &manager)
                for rule in activatedRules {
                    findings.append(contentsOf: rule.findings(in: parsed))
                }
            }
        }
        return findings
    }

    static func parsedSource(
        at path: Swift.String,
        manager: inout Source.Manager
    ) throws(Error) -> Lint.Source.Parsed {
        let filePath: File.Path
        do {
            filePath = try File.Path(path)
        } catch {
            throw .fileNotReadable(path: path)
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
            throw .fileNotReadable(path: path)
        }
        let text = Swift.String(decoding: bytes, as: UTF8.self)
        let id = manager.register(fileID: path, filePath: path, content: bytes)
        let sourceFile = manager.file(for: id)
        let tree = Parser.parse(source: text)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        return Lint.Source.Parsed(file: sourceFile, tree: tree, converter: converter)
    }
}
