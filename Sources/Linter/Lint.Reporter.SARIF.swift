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

public import JSON
public import Terminal_Primitives

/// SARIF 2.1.0 reporter — emits a single sarifLog object covering all
/// findings from one run.
///
/// Suitable for CI artifact upload (GitHub Code Scanning, GitLab SAST, Azure
/// DevOps Advanced Security).
///
/// Reference: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
///
/// JSON serialization composes `swift-foundations/swift-json` (Foundation-
/// clean; backed by RFC 8259). Builds a `JSON` value via the package's
/// literal-rich API and serializes via `JSON.serialize(pretty:)`.
///
/// Phase 1.5: report emits via `Terminal.Stream.Write` (the typed write
/// surface from `swift-terminal-primitives`) plus a consumer-supplied
/// emit closure, mirroring the text reporter's pattern. SARIF is a
/// single-shot document (one JSON object per run) so the emit fires
/// once with the full payload.
extension Lint.Reporter {
    public enum SARIF {}
}

extension Lint.Reporter.SARIF {
    /// Emit a SARIF report via the given write surface.
    public static func emit(
        findings: [Lint.Finding],
        to write: Terminal.Stream.Write,
        via emit: (Terminal.Stream.Write, Swift.String) -> Void
    ) {
        emit(write, report(for: findings))
    }

    /// Build the SARIF document as a String (testable; CLI uses `emit`).
    public static func report(for findings: [Lint.Finding]) -> Swift.String {
        let document = sarifLog(for: findings)
        return document.serialize(pretty: true)
    }

    static func sarifLog(for findings: [Lint.Finding]) -> JSON {
        [
            "version": "2.1.0",
            "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/cs01/schemas/sarif-schema-2.1.0.json",
            "runs": [
                [
                    "tool": [
                        "driver": [
                            "name": "swift-linter",
                            "informationUri": "https://swift-institute.org",
                            "rules": [],
                        ],
                    ],
                    "results": JSON.array(findings.map(result(for:))),
                ],
            ],
        ]
    }

    static func result(for finding: Lint.Finding) -> JSON {
        let pathOrID = finding.location.filePath ?? finding.location.fileID
        return [
            "ruleId": JSON(stringLiteral: finding.identifier),
            "level": JSON(stringLiteral: level(for: finding.severity)),
            "message": ["text": JSON(stringLiteral: finding.message)],
            "locations": [
                [
                    "physicalLocation": [
                        "artifactLocation": ["uri": JSON(stringLiteral: pathOrID)],
                        "region": [
                            "startLine": JSON(integerLiteral: finding.location.line),
                            "startColumn": JSON(integerLiteral: finding.location.column),
                        ],
                    ],
                ],
            ],
        ]
    }

    static func level(for severity: Diagnostic.Severity) -> Swift.String {
        switch severity {
        case .error: "error"
        case .warning: "warning"
        case .note: "note"
        case .remark: "note"
        }
    }
}
