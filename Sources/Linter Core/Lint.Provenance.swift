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
public import Linter_Primitives
import SwiftParser
import SwiftSyntax

/// Vendored-fork provenance scoping (swift-foundations/swift-linter#45).
///
/// Institute lint rules govern Institute-authored code. A repository that
/// is a true fork of upstream open-source code carries vendored source
/// under a different project's copyright, and running Institute-authored
/// rules against that source is a category error — the findings describe
/// code the Institute did not write and does not rewrite.
///
/// The exemption is TYPED and CENTRALLY OWNED (the enforcement doctrine's
/// exception discipline): fork provenance is declared HERE, in the
/// engine's own ``Lint/Provenance/Register``, never in a consumer's
/// configuration. A consumer cannot add, widen, or edit an entry — the
/// declaration is reviewed and removed through this repository. What the
/// declaration scopes is the run's INPUT (which files are linted), never
/// which rules apply and never what severity fails the run.
extension Lint {
    /// Namespace for centrally declared vendored-fork provenance and its
    /// resolution against a run root.
    public enum Provenance {}
}

extension Lint.Provenance {
    /// Resolves the centrally declared fork entry, if any, for the
    /// package rooted at `root`.
    ///
    /// Identity is the SwiftPM package name declared in `root`'s own
    /// `Package.swift` — the same identity SwiftPM derives overrides
    /// from, and the narrowest stable property a run root exposes. A
    /// missing or unreadable manifest, a manifest with no extractable
    /// package name, and a name absent from ``Register/declared`` all
    /// resolve to `nil`: every failure direction is toward LINTING, so a
    /// repository merely resembling a declared fork is fully linted.
    public static func resolve(root: File.Path) -> Fork? {
        let manifest: File.Path
        do throws(Paths.Path.Error) {
            manifest = root.appending(try File.Path("Package.swift"))
        } catch {
            return nil
        }
        let bytes: [Byte]
        do throws(Either<File.System.Read.Full.Error, Never>) {
            bytes = try File(manifest).read.full { (span: Swift.Span<Byte>) in
                var copy: [Byte] = []
                copy.reserveCapacity(span.count)
                span.indices.forEach { copy.append(span[$0]) }
                return copy
            }
        } catch {
            return nil
        }
        guard let text = Swift.String(validating: bytes, as: UTF8.self) else {
            return nil
        }
        guard let name = Self.package(inManifest: text) else { return nil }
        return Register.declared.first { $0.package == name }
    }

    /// Extracts the declared SwiftPM package name from manifest source.
    ///
    /// Syntax-directed, not textual: the manifest is parsed and the
    /// FIRST `Package(...)` initializer call's `name:` argument is read,
    /// provided it is a plain single-segment string literal. Product and
    /// target `name:` arguments cannot shadow it — they live in nested
    /// calls whose callee is not `Package`. Interpolated or multi-segment
    /// literals resolve to `nil` (toward linting).
    internal static func package(inManifest text: Swift.String) -> Swift.String? {
        let tree = Parser.parse(source: text)
        let visitor = Manifest.Visitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        return visitor.package
    }
}
