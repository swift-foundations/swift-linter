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

/// SARIF 2.1.0 reporter — emits a single sarifLog object covering all
/// findings from one run.
///
/// Suitable for CI artifact upload (GitHub Code Scanning, GitLab SAST, Azure
/// DevOps Advanced Security).
///
/// Reference: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
///
/// **Open Question (surfaced 2026-05-06)**: SARIF emission is hand-rolled
/// string interpolation. If a higher-layer JSON encoding primitive becomes
/// available (or `swift-coder-primitives` provides Codable + JSON
/// orchestration), this reporter should compose it. For Phase 1, hand-rolled
/// JSON keeps the dependency surface minimal.
extension Lint.Reporter {
    public enum SARIF {}
}

extension Lint.Reporter.SARIF {
    public static func report(for findings: [Lint.Finding]) -> Swift.String {
        let runs = runs(for: findings)
        return """
        {
          "version": "2.1.0",
          "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/cs01/schemas/sarif-schema-2.1.0.json",
          "runs": \(runs)
        }
        """
    }

    static func runs(for findings: [Lint.Finding]) -> Swift.String {
        let results = findings.map(result(for:)).joined(separator: ",\n")
        return """
        [
          {
            "tool": {
              "driver": {
                "name": "swift-linter",
                "informationUri": "https://swift-institute.org",
                "rules": []
              }
            },
            "results": [
        \(results)
            ]
          }
        ]
        """
    }

    static func result(for finding: Lint.Finding) -> Swift.String {
        let pathOrID = finding.location.filePath ?? finding.location.fileID
        return """
              {
                "ruleId": "\(escape(finding.ruleID))",
                "level": "\(level(for: finding.severity))",
                "message": { "text": "\(escape(finding.message))" },
                "locations": [
                  {
                    "physicalLocation": {
                      "artifactLocation": { "uri": "\(escape(pathOrID))" },
                      "region": { "startLine": \(finding.location.line), "startColumn": \(finding.location.column) }
                    }
                  }
                ]
              }
        """
    }

    static func level(for severity: Diagnostic.Severity) -> Swift.String {
        switch severity {
        case .error: "error"
        case .warning: "warning"
        case .note: "note"
        case .remark: "note"
        }
    }

    static func escape(_ string: Swift.String) -> Swift.String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(character)
            }
        }
        return result
    }
}
