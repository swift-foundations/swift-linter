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

public import Linter_Primitives
public import Linter_Reporter_Text
public import JSON
public import Terminal_Primitives

#if !os(Windows)
public import ISO_9945_Kernel_Terminal
#else
public import Windows_32_Kernel_Terminal
#endif

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
/// Phase 2 Stream C: report writes directly to `Terminal.Stream.Write`
/// via the L2 syscall extension. SARIF is a single-shot document (one
/// JSON object per run) so the write fires once with the full payload.
extension Lint.Reporter {
    public enum SARIF {}
}

extension Lint.Reporter.SARIF {
    /// Emit a SARIF report via the given write surface.
    public static func emit(
        findings: [Lint.Finding],
        to write: Terminal.Stream.Write
    ) {
        try? write((report(for: findings) + "\n").utf8)
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
        let record = finding.record
        let pathOrID = record.location.filePath ?? record.location.fileID
        return [
            "ruleId": JSON(stringLiteral: record.identifier),
            "level": JSON(stringLiteral: level(for: record.severity)),
            "message": ["text": JSON(stringLiteral: record.message)],
            "locations": [
                [
                    "physicalLocation": [
                        "artifactLocation": ["uri": JSON(stringLiteral: pathOrID)],
                        "region": [
                            "startLine": JSON(integerLiteral: record.location.line),
                            "startColumn": JSON(integerLiteral: record.location.column),
                        ],
                    ],
                ],
            ],
        ]
    }

    /// SARIF maps `.remark → "note"` (SARIF's level vocabulary is
    /// `error / warning / note / none`; remark has no SARIF analog).
    /// All other tokens defer to `Diagnostic.Severity.wireToken`.
    static func level(for severity: Diagnostic.Severity) -> Swift.String {
        switch severity {
        case .remark: "note"
        default: severity.wireToken
        }
    }
}
