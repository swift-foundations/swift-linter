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

public import Cardinal_Primitives
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
                _ = try write((line(for: finding) + "\n").utf8.lazy.map(Byte.init))
            } catch {
                // Best-effort stdout write; broken pipe is acceptable for
                // a textual diagnostic emitter (the conventional behavior
                // when stdout's reader has closed).
            }
        }
    }

    /// Emit the always-on one-line run summary to `write` (the engine passes
    /// **stderr** — stdout stays the pure diagnostic stream). Emitted on EVERY
    /// run, including a 0-violation one, so a clean run is self-evidently a real
    /// run rather than a silent no-op.
    ///
    /// Shape: `<package> · <K> active rules[ (−<M> excluded)] · <F> files linted · <V> violations`.
    /// `K` is the *effective* active-rule count (after bundle composition AND
    /// any runtime overlay/exclusions), so it reflects what actually ran; `M`
    /// (the runtime-disabled count) annotates the overlay/exclusion case.
    ///
    /// The four counts are typed `Tagged<Domain, Cardinal>` — a *cardinal of
    /// rules / source files / findings* — rather than bare `Int` so the
    /// reporter's public surface reads typed intent (`[IMPL-010]`). These spell
    /// the same underlying types as Linter Core's `Lint.Rule.Count` /
    /// `Lint.Source.Count` / `Lint.Finding.Count` aliases; Reporter Text cannot
    /// import Linter Core (sibling targets), so the `Tagged<…>` form is written
    /// out here. The eventual single home is swift-linter-primitives.
    public static func emit(
        summaryFor package: Swift.String,
        activeRules: Tagged<Lint.Rule, Cardinal>,
        excludedRules: Tagged<Lint.Rule, Cardinal>,
        filesLinted: Tagged<Lint.Source, Cardinal>,
        violations: Tagged<Lint.Finding, Cardinal>,
        to write: Terminal.Stream.Write
    ) {
        let line: Swift.String = Summary.line(
            package: package,
            activeRules: activeRules,
            excludedRules: excludedRules,
            filesLinted: filesLinted,
            violations: violations
        )
        do throws(ISO_9945.Kernel.IO.Write.Error) {
            _ = try write((line + "\n").utf8.lazy.map(Byte.init))
        } catch {
            // Best-effort stderr write; broken pipe acceptable.
        }
    }

    /// Emit a one-line `[Lint] error: <message>` diagnostic via `write` (the
    /// caller passes **stderr** — stdout stays the pure diagnostic stream).
    ///
    /// Used by the consumer entry points (`Lint.run(bundle:)` /
    /// `Lint.run(dependencies:rules:)`) to fail LOUD when a selection / parent
    /// ``Lint/File/Single/Channel`` read hard-errors — the message goes to
    /// stderr immediately before the process exits non-zero, so a
    /// set-but-unreadable manifest can never be mistaken for a clean run. Write
    /// errors are swallowed best-effort, matching the other emitters.
    public static func emit(
        error message: Swift.String,
        to write: Terminal.Stream.Write
    ) {
        do throws(ISO_9945.Kernel.IO.Write.Error) {
            _ = try write(("[Lint] error: " + message + "\n").utf8.lazy.map(Byte.init))
        } catch {
            // Best-effort stderr write; broken pipe acceptable.
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
