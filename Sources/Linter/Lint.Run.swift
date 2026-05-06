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
public import struct Foundation.URL
public import struct Foundation.Data

/// Run the linter against one or more paths.
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
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .fileNotReadable(path: path)
        }
        guard let text = Swift.String(data: data, encoding: .utf8) else {
            throw .nonUTF8(path: path)
        }
        let bytes = Array(text.utf8)
        let id = manager.register(fileID: path, filePath: path, content: bytes)
        let file = manager.file(for: id)
        let tree = Parser.parse(source: text)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        return Lint.Source.Parsed(file: file, tree: tree, converter: converter)
    }
}
