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

public import File_System
internal import Version_Primitives

extension Lint.File.Single {
    /// Shape-γ detection: is there a `Lint.swift` at the consumer root carrying
    /// the `// swift-linter-tools-version:` magic-comment header?
    ///
    /// Detection is a pure, side-effect-free read used by the CLI to choose the
    /// single-file dispatch path over the nested-package / legacy paths. It is
    /// the consumer-facing entry that ``dispatch(at:arguments:output:nonce:)``'s
    /// own magic-comment re-check mirrors.
    public enum Detection: Swift.Sendable {}
}

extension Lint.File.Single.Detection {
    /// The magic-comment header that identifies a Shape-γ `Lint.swift`.
    ///
    /// Matched case-sensitively in the file's first leading-trivia block. Files
    /// without this header are NOT treated as Shape-γ — callers fall through to
    /// the next detection path.
    public static let header: Swift.String = "swift-linter-tools-version:"

    /// Detect whether `<consumerPackageRoot>/Lint.swift` exists AND carries the
    /// Shape-γ magic-comment header.
    ///
    /// Returns the path to the file when detection succeeds, `nil` otherwise.
    /// The magic-comment check is line-by-line over the file's first 30 lines
    /// (sufficient for the institute's canonical scaffolds; SE-0152 SwiftPM
    /// places the analogous `swift-tools-version:` directive at line 1).
    ///
    /// F-A2.3 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
    /// `consumerPackageRoot` is typed `File.Path`; the returned candidate path
    /// is also typed.
    public static func detect(at consumerPackageRoot: File.Path) -> File.Path? {
        let candidate: File.Path = consumerPackageRoot / "Lint.swift"
        // Existence is a single typed `Stat.isFile` query — not a directory
        // validate + `entries()` enumeration + name loop (which reinvented what
        // swift-file-system already provides). A missing directory, a missing
        // file, or a non-regular entry all yield `false` → the silent-fallback
        // "no Shape-γ manifest detected", and the caller moves on.
        guard File.System.Stat.isFile(at: candidate) else { return nil }
        let source: Swift.String
        do throws(File.System.Read.Full.Error) {
            source = try Lint.File.Single.contents(of: candidate)
        } catch {
            return nil
        }
        return Self.hasMagicComment(in: source) ? candidate : nil
    }

    /// Detect whether the leading 30 lines of `source` contain a Shape-γ
    /// magic-comment line whose version parses as ``Version/Tools``.
    internal static func hasMagicComment(in source: Swift.String) -> Swift.Bool {
        Self.parseMagicCommentToolsVersion(in: source) != nil
    }

    /// Scan the leading 30 lines of `source` for the ``header`` substring and
    /// parse the typed ``Version/Tools`` value that follows it.
    ///
    /// Returns `nil` when no magic-comment line is present, OR when the version
    /// following the header fails to parse as ``Version/Tools``.
    fileprivate static func parseMagicCommentToolsVersion(
        in source: Swift.String
    ) -> Version.Tools? {
        var lineCount = 0
        for line in source.split(separator: "\n", maxSplits: 30, omittingEmptySubsequences: false) {
            if line.contains(Self.header) {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                var versionSlice = parts[1]
                while let first = versionSlice.first, first == " " || first == "\t" {
                    versionSlice = versionSlice.dropFirst()
                }
                while let last = versionSlice.last, last == " " || last == "\t" {
                    versionSlice = versionSlice.dropLast()
                }
                return Version.Tools(Swift.String(versionSlice))
            }
            lineCount += 1
            if lineCount >= 30 { break }
        }
        return nil
    }
}
