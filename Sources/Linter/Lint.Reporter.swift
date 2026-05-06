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

/// Default text-format reporter — one `file:line:col: severity: ruleID: message`
/// line per finding.
///
/// Format matches SwiftLint's textual shape so existing CI parsers / IDE
/// problem-matchers detect findings without configuration changes.
///
/// **Open Question (surfaced 2026-05-06)**: `swift-terminal-primitives` does
/// not yet expose a `Stream.Write` accessor — it provides only the
/// `Terminal.Stream` enum (.stdin/.stdout/.stderr) and a `.read` accessor.
/// The library-side reporter therefore returns formatted strings; the CLI
/// target's main.swift performs the I/O. Once `Stream.Write` exists, the
/// reporter can compose it directly for higher-fidelity output (severity
/// colors, hyperlinked locations).
extension Lint {
    public enum Reporter {}
}

extension Lint.Reporter {
    public static func text(for findings: [Lint.Finding]) -> Swift.String {
        findings
            .map(line(for:))
            .joined(separator: "\n")
    }

    public static func line(for finding: Lint.Finding) -> Swift.String {
        let location = finding.location
        let pathOrID = location.filePath ?? location.fileID
        let prefix = "\(pathOrID):\(location.line):\(location.column): "
        let severity = "\(severityToken(for: finding.severity)): "
        let body = "\(finding.identifier): \(finding.message)"
        return prefix + severity + body
    }

    static func severityToken(for severity: Diagnostic.Severity) -> Swift.String {
        switch severity {
        case .error: "error"
        case .warning: "warning"
        case .note: "note"
        case .remark: "remark"
        }
    }
}
