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

#if !os(Windows)
public import ISO_9945_Kernel_Terminal
#else
public import Windows_32_Kernel_Terminal
#endif

/// Default text-format reporter — one `file:line:col: severity: identifier:
/// message` line per finding.
///
/// Format matches SwiftLint's textual shape so existing CI parsers / IDE
/// problem-matchers detect findings without configuration changes.
///
/// Phase 2 Stream C: Reporter writes directly to `Terminal.Stream.Write`
/// via the L2 syscall extension (POSIX: `swift-iso-9945`; Windows:
/// `swift-windows-32`). The earlier closure stand-in (Phase 1.5) was
/// removed once OQ-T2 closed.
extension Lint {
    public enum Reporter {}
}

extension Lint.Reporter {
    /// Emit findings as text lines via the given write surface.
    ///
    /// One line per finding, each terminated with a single `\n`. Errors
    /// from the underlying syscall are silently dropped — the CLI's exit
    /// path doesn't model output-stream failures, and partial output (a
    /// truncated last line on a closed pipe) is the conventional behavior
    /// for textual diagnostic emitters.
    public static func emit(
        findings: [Lint.Finding],
        to write: Terminal.Stream.Write
    ) {
        for finding in findings {
            try? write((line(for: finding) + "\n").utf8)
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
        let severity = "\(finding.severity.wireToken): "
        let body = "\(finding.identifier): \(finding.message)"
        return prefix + severity + body
    }
}
