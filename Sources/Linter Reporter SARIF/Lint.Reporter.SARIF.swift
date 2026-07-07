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
public import Linter_Primitives
public import Linter_Reporter_Text
public import Terminal_Primitives

// REASON: Phase 2 Stream C (OQ-T2 closed) — Reporter writes directly via the L2 terminal
// syscall extension per platform; the OS-conditional import is the deliberate unification
// boundary chosen when the Phase 1.5 closure stand-in was retired, not undifferentiated L1
// primitive code.
// swiftlint:disable:next l1_no_platform_conditionals
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
    /// SARIF 2.1.0 reporter namespace — emits a single sarifLog object per run.
    public enum SARIF {}
}

extension Lint.Reporter.SARIF {
    /// Emit a SARIF report via the given write surface.
    public static func emit(
        findings: [Lint.Finding],
        to write: Terminal.Stream.Write
    ) {
        do throws(ISO_9945.Kernel.IO.Write.Error) {
            _ = try write((report(for: findings) + "\n").utf8.lazy.map(Byte.init))
        } catch {
            // Best-effort stdout write; broken pipe is acceptable for
            // a textual diagnostic emitter (the conventional behavior
            // when stdout's reader has closed).
        }
    }

    /// Build the SARIF document as a String (testable; CLI uses `emit`).
    public static func report(for findings: [Lint.Finding]) -> Swift.String {
        let document = sarifLog(for: findings)
        return document.serialize(pretty: true)
    }

    fileprivate static func sarifLog(for findings: [Lint.Finding]) -> JSON {
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
                        ]
                    ],
                    "results": JSON.array(findings.map(result(for:))),
                ]
            ],
        ]
    }

    /// Map one ``Lint/Finding`` to its SARIF `result` object.
    ///
    /// When the finding carries a non-`nil` ``Lint/Finding/visibility``,
    /// the `properties` bag receives a `visibility` field with the
    /// enum's raw value (`"public"` / `"internal"` / `"fileprivate"` /
    /// `"private"`). SARIF 2.1.0 admits arbitrary property bags on
    /// `result` (§3.27.16), so consumers ignoring the field experience
    /// no change in schema conformance.
    static func result(for finding: Lint.Finding) -> JSON {
        let record = finding.record
        let pathOrID = record.location.filePath ?? record.location.fileID
        var fields: [(Swift.String, JSON)] = [
            ("ruleId", JSON(stringLiteral: record.identifier)),
            ("level", JSON(stringLiteral: level(for: record.severity))),
            ("message", ["text": JSON(stringLiteral: record.message)] as JSON),
            (
                "locations",
                [
                    [
                        "physicalLocation": [
                            "artifactLocation": ["uri": JSON(stringLiteral: pathOrID)],
                            "region": [
                                "startLine": JSON(integerLiteral: Int(record.location.line.underlying)),
                                "startColumn": JSON(integerLiteral: Int(bitPattern: record.location.column)),
                            ],
                        ]
                    ]
                ] as JSON
            ),
        ]
        if let visibility = finding.visibility {
            // swift-linter:disable:next raw value access
            // REASON: `Lint.Visibility` is a `String`-backed `RawRepresentable` enum
            // (`case public`/`internal`/…), NOT a Tagged newtype; `.rawValue` is the
            // canonical access for its wire token at this SARIF serialization boundary.
            // The rule's display/serialization disposition ([PATTERN-017]).
            let token: Swift.String = visibility.rawValue
            fields.append(
                (
                    "properties",
                    ["visibility": JSON(stringLiteral: token)] as JSON
                )
            )
        }
        return JSON.object(fields)
    }

    /// SARIF maps `.remark → "note"` (SARIF's level vocabulary is
    /// `error / warning / note / none`; remark has no SARIF analog).
    ///
    /// All other tokens defer to `Diagnostic.Severity.wireToken`.
    static func level(for severity: Diagnostic.Severity) -> Swift.String {
        switch severity {
        case .remark: "note"
        default: severity.wireToken
        }
    }
}
