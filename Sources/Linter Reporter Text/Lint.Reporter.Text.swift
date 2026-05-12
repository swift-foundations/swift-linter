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
extension Lint.Reporter {
    public enum Text {}
}

extension Lint.Reporter.Text {
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
            do throws(ISO_9945.Kernel.IO.Write.Error) {
                _ = try write((line(for: finding) + "\n").utf8)
            } catch {
                // Best-effort stdout write; broken pipe is acceptable for
                // a textual diagnostic emitter (the conventional behavior
                // when stdout's reader has closed).
            }
        }
    }

    /// Format all findings as a single text block (one line per finding).
    ///
    /// Convenience for testing and for consumers that prefer batch
    /// String construction over line-by-line emit.
    public static func report(for findings: [Lint.Finding]) -> Swift.String {
        findings
            .map(line(for:))
            .joined(separator: "\n")
    }

    /// Format a single finding as a SwiftLint-compatible textual line.
    ///
    /// Shape: `<path>:<line>:<column>: <severity>: <identifier>: <message>`
    /// — matching SwiftLint's textual reporter form so existing CI
    /// parsers / IDE problem-matchers detect findings without
    /// configuration changes.
    ///
    /// When the finding carries a non-`nil` ``Lint/Finding/visibility``
    /// the line is suffixed with ` [visibility: <case>]` (e.g.,
    /// `[visibility: private]`). Visibility annotation is engine-
    /// computed metadata; consumers parsing the SwiftLint shape
    /// strictly can ignore the bracketed suffix — the
    /// `path:line:col: severity:` prefix is unchanged.
    public static func line(for finding: Lint.Finding) -> Swift.String {
        let record = finding.record
        let location = record.location
        let pathOrID = location.filePath ?? location.fileID
        let prefix = "\(pathOrID):\(location.line):\(location.column): "
        let severity = "\(record.severity.wireToken): "
        let body = "\(record.identifier): \(record.message)"
        let line = prefix + severity + body
        guard let visibility = finding.visibility else { return line }
        return line + " [visibility: \(visibility.rawValue)]"
    }
}
