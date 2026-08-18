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

// REASON: Phase 2 Stream C (OQ-T2 closed) — Reporter writes directly via the L2 terminal
// syscall extension per platform; the OS-conditional import is the deliberate unification
// boundary chosen when the Phase 1.5 closure stand-in was retired, not undifferentiated L1
// primitive code.
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
    /// Default text-format reporter namespace — SwiftLint-compatible textual lines.
    public enum Text {}
}

extension Lint.Reporter.Text {
    /// The kernel write-syscall error thrown by `Terminal.Stream.Write` on
    /// this platform, resolved the same way as the OS-conditional import
    /// above: POSIX -> `ISO_9945.Kernel.IO.Write.Error` (`write(2)`);
    /// Windows -> `Windows.`32`.Kernel.IO.Write.Error` (`WriteFile`). Both
    /// modules are already brought into scope transitively (each
    /// `@_exported import`s its Kernel Core) by the conditional import
    /// above. Mirrors `Process.Error.Kernel`'s per-platform typealias shape.
    #if !os(Windows)
        fileprivate typealias Kernel = ISO_9945.Kernel.IO.Write.Error
    #else
        fileprivate typealias Kernel = Windows.`32`.Kernel.IO.Write.Error
    #endif
}

extension Lint.Reporter.Text {
    /// Adapts a line's UTF-8 bytes to the exact `Sequence` element type this
    /// platform's `Terminal.Stream.Write.callAsFunction` parameter requires.
    ///
    /// The two L2 syscall extensions are not parameter-symmetric today:
    /// POSIX (`swift-iso-9945`) takes `some Sequence<Byte>`; Windows
    /// (`swift-windows-32`) takes `some Sequence<UInt8>` (its L2 write
    /// surface predates the Byte-typed POSIX one — see the "future Windows"
    /// note on `Terminal.Stream.Write` in swift-terminal-primitives). `Byte`
    /// is a distinct wrapper struct, not a `UInt8` typealias, so the two
    /// element types do not unify — this reporter must supply whichever one
    /// the platform's `write` actually declares.
    #if !os(Windows)
        fileprivate static func bytes(of text: Swift.String) -> [Byte] {
            text.utf8.map(Byte.init)
        }
    #else
        fileprivate static func bytes(of text: Swift.String) -> [Swift.UInt8] {
            Swift.Array(text.utf8)
        }
    #endif
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
            do throws(Kernel) {
                _ = try write(bytes(of: line(for: finding) + "\n"))
            } catch {
                // Best-effort stdout write; broken pipe is acceptable for
                // a textual diagnostic emitter (the conventional behavior
                // when stdout's reader has closed).
            }
        }
    }

    // REASON: a formatting entry point — five display-only counts, a subject, and a sink.
    // Region form, not `disable:next`: an intervening line comment would orphan the doc
    // comment below it.
    // swiftlint:disable function_parameter_count

    /// Emit the always-on one-line run summary to `write` (the engine passes
    /// **stderr** — stdout stays the pure diagnostic stream).
    ///
    /// Emitted on EVERY
    /// run, including a 0-violation one, so a clean run is self-evidently a real
    /// run rather than a silent no-op.
    ///
    /// Shape: `<package> · <K> active rules[ (−<M> excluded)] · <F> files linted · <V> violations · <N> findings`.
    /// `K` is the *effective* active-rule count (after bundle composition AND
    /// any runtime overlay/exclusions), so it reflects what actually ran; `M`
    /// (the runtime-disabled count) annotates the overlay/exclusion case.
    /// `violations` keeps its unchanged semantics (excludes `.note`/`.remark`;
    /// still drives the strict exit policy); `findings` is the total surfaced
    /// count, exactly the population the SARIF reporter serializes as
    /// `results` (swift-foundations/swift-linter#22).
    ///
    /// The five counts are bare `Int` — display-only cardinalities formatted
    /// into this one line, never indexed or arithmetic-combined. Typing them
    /// (`Count` / `Index<Element>.Count`) would pull a cardinal/collection
    /// dependency tree into the reporter for no semantic gain; leanness wins
    /// for display values (the `int public parameter` finding here is a known,
    /// accepted advisory).
    public static func emit(
        summaryFor package: Swift.String,
        activeRules: Swift.Int,
        excludedRules: Swift.Int,
        filesLinted: Swift.Int,
        violations: Swift.Int,
        findings: Swift.Int,
        to write: Terminal.Stream.Write
    ) {
        let line: Swift.String = Summary.line(
            package: package,
            activeRules: activeRules,
            excludedRules: excludedRules,
            filesLinted: filesLinted,
            violations: violations,
            findings: findings
        )
        do throws(Kernel) {
            _ = try write(bytes(of: line + "\n"))
        } catch {
            // Best-effort stderr write; broken pipe acceptable.
        }
    }

    // swiftlint:enable function_parameter_count

    /// Emit `text` verbatim via `write`, adding nothing.
    ///
    /// The one emitter here that does not impose a shape, for output whose
    /// shape is the point: a fix run's unified diffs must survive a round
    /// trip through `git apply`, and a reporter that prefixed or re-wrapped
    /// them would break that. Write errors are swallowed best-effort,
    /// matching the other emitters.
    public static func emit(
        text: Swift.String,
        to write: Terminal.Stream.Write
    ) {
        do throws(Kernel) {
            _ = try write(bytes(of: text))
        } catch {
            // Best-effort write; broken pipe acceptable.
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
        do throws(Kernel) {
            _ = try write(bytes(of: "[Lint] error: " + message + "\n"))
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
        let severity = "\(record.severity.wire.token): "
        let body = "\(record.identifier): \(record.message)"
        let line = prefix + severity + body
        guard let visibility = finding.visibility else { return line }
        // swift-linter:disable:next raw value access
        // REASON: `Lint.Visibility` is a `String`-backed `RawRepresentable` enum
        // (`case public`/`internal`/…), NOT a Tagged newtype; `.rawValue` is the
        // canonical access for its wire token at this text-display boundary. The
        // rule's display/serialization disposition ([PATTERN-017]).
        let token: Swift.String = visibility.rawValue
        return line + " [visibility: \(token)]"
    }
}
