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

public import struct Foundation.URL
public import class Foundation.FileManager
public import struct Foundation.Data

/// Hand-rolled minimal YAML loader for the linter's flat config schema.
///
/// Supports a single tag — `rules:` — followed by a block-style list of rule
/// IDs. Comments (`#`) and blank lines are skipped. No `parent_config:`
/// chaining in Phase 1; full YAML compliance is deferred. When the chain
/// arrives, this type is the natural place to host it.
extension Lint.Configuration {
    public enum Loader {}
}

extension Lint.Configuration.Loader {
    public static func load(
        from path: Swift.String,
        knownRuleIDs: Set<Lint.Rule.ID>
    ) throws(Lint.Configuration.Error) -> Lint.Configuration {
        let manager = FileManager.default
        guard manager.fileExists(atPath: path) else {
            throw .fileNotReadable(path: path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw .fileNotReadable(path: path)
        }
        guard let text = Swift.String(data: data, encoding: .utf8) else {
            throw .malformed(path: path, reason: "non-UTF-8 file")
        }
        return try parse(text: text, path: path, knownRuleIDs: knownRuleIDs)
    }

    public static func parse(
        text: Swift.String,
        path: Swift.String,
        knownRuleIDs: Set<Lint.Rule.ID>
    ) throws(Lint.Configuration.Error) -> Lint.Configuration {
        var activated: Set<Lint.Rule.ID> = []
        var inRulesBlock = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = Swift.String(rawLine)
            let stripped = line.split(separator: "#", maxSplits: 1).first.map(Swift.String.init) ?? ""
            let trimmed = stripped.trimmed
            if trimmed.isEmpty { continue }
            if trimmed == "rules:" {
                inRulesBlock = true
                continue
            }
            if inRulesBlock, let ruleID = ruleID(from: trimmed) {
                guard knownRuleIDs.contains(ruleID) else {
                    throw .unknownRuleID(ruleID, path: path)
                }
                activated.insert(ruleID)
                continue
            }
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && line.contains(":") {
                inRulesBlock = false
            }
        }
        return Lint.Configuration(activatedRuleIDs: activated)
    }

    static func ruleID(from line: Swift.String) -> Lint.Rule.ID? {
        let trimmed = line.trimmed
        guard trimmed.hasPrefix("- ") else { return nil }
        let value = trimmed.dropFirst(2).trimmed
        return value.isEmpty ? nil : Lint.Rule.ID(value)
    }
}

extension Swift.String {
    fileprivate var trimmed: Swift.String {
        var view = self[...]
        while let first = view.first, first.isWhitespace { view = view.dropFirst() }
        while let last = view.last, last.isWhitespace { view = view.dropLast() }
        return Swift.String(view)
    }
}

extension Substring {
    fileprivate var trimmed: Swift.String {
        var view = self
        while let first = view.first, first.isWhitespace { view = view.dropFirst() }
        while let last = view.last, last.isWhitespace { view = view.dropLast() }
        return Swift.String(view)
    }
}
