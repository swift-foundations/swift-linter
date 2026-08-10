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

extension Lint.Provenance {
    /// One declared unit of vendored scope inside a fork repository —
    /// either a whole directory subtree or one exact file, both stated
    /// run-root-relative.
    ///
    /// The scope is an explicit enumeration, never a glob: an
    /// Institute-authored file added anywhere in the fork defaults to
    /// LINTED unless a directory entry deliberately covers its location.
    public enum Scope: Sendable, Hashable {
        /// Every Swift file at any depth under this run-root-relative
        /// directory (e.g. `"Sources/X509"`).
        case directory(Swift.String)

        /// Exactly this run-root-relative file
        /// (e.g. `"Tests/X509Tests/Fixtures.swift"`).
        case file(Swift.String)
    }
}

extension Lint.Provenance.Scope {
    /// Whether the walker-emitted run-root-relative `path` lies inside
    /// this scope.
    ///
    /// This is a path-scoped exemption, the class of check that goes
    /// wrong most often and most quietly, so it is spelled to the
    /// discipline that class requires. Matching is on whole path
    /// SEGMENTS: a ``directory(_:)`` entry first drops the candidate's
    /// trailing filename, then requires its own segments to be a
    /// leading run of the remaining directory segments — so
    /// `Sources/X509` never admits `Sources/X509Extra/…`, and a bare
    /// filename with no directory component is never admitted by any
    /// directory entry. A ``file(_:)`` entry requires segment-for-segment
    /// equality of the whole path. Neither `contains` nor a raw string
    /// prefix test is used.
    public func matches(_ path: Lint.Source.Path) -> Swift.Bool {
        let candidate: [Swift.Substring] =
            path.underlying
            .split(separator: "/", omittingEmptySubsequences: true)
        guard !candidate.isEmpty else { return false }
        switch self {
        case .directory(let declared):
            let scope: [Swift.Substring] =
                declared
                .split(separator: "/", omittingEmptySubsequences: true)
            let directories = candidate.dropLast()
            guard !scope.isEmpty, directories.count >= scope.count else { return false }
            return directories.prefix(scope.count).elementsEqual(scope)
        case .file(let declared):
            let scope: [Swift.Substring] =
                declared
                .split(separator: "/", omittingEmptySubsequences: true)
            return candidate.elementsEqual(scope)
        }
    }
}
