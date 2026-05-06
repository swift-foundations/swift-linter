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

public import Terminal_Primitives

/// Default text-format reporter — one `file:line:col: severity: identifier:
/// message` line per finding.
///
/// Format matches SwiftLint's textual shape so existing CI parsers / IDE
/// problem-matchers detect findings without configuration changes.
///
/// Phase 1.5: Reporter consumes `Terminal.Stream.Write` (the typed write
/// surface from `swift-terminal-primitives`) instead of returning Strings.
/// The CLI binds an emit closure at the I/O boundary; the L2 syscall
/// callAsFunction extension on `Terminal.Stream.Write` is a future
/// dispatch (see Open Question OQ-T2 in the Phase 1.5 HANDOFF). Until L2
/// fills in the syscall, the CLI provides the emit via a Swift stdlib
/// fallback — typed at the API surface, byte-emitting via the consumer.
extension Lint {
    public enum Reporter {}
}

extension Lint.Reporter {
    /// Emit findings as text lines via the given write surface.
    ///
    /// The `emit` parameter is a closure that performs the actual write.
    /// Until `Terminal.Stream.Write` gains an L2 syscall extension,
    /// consumers (e.g., the CLI) supply this closure at the I/O boundary
    /// — typically wrapping `Swift.print(...)` or an equivalent FD write.
    public static func emit(
        findings: [Lint.Finding],
        to write: Terminal.Stream.Write,
        via emit: (Terminal.Stream.Write, Swift.String) -> Void
    ) {
        for finding in findings {
            emit(write, line(for: finding))
        }
    }

    /// Format all findings as a single text block (one line per finding).
    ///
    /// Convenience for testing and for consumers that prefer batch
    /// String construction over line-by-line emit.
    public static func text(for findings: [Lint.Finding]) -> Swift.String {
        findings
            .map(line(for:))
            .joined(separator: "\n")
    }

    /// Format a single finding as a SwiftLint-compatible textual line.
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
