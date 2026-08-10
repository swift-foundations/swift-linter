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

internal import Linter_Primitives

extension Lint.Provenance.Fork {
    /// The upstream ancestry a declared fork asserts: the repository the
    /// vendored source was forked from and the exact commit at the fork
    /// point.
    public struct Upstream: Sendable, Hashable {
        /// The upstream repository, `owner/name`
        /// (e.g. `"apple/swift-certificates"`).
        public let repository: Swift.String

        /// The full 40-hex-digit commit at the fork point.
        public let commit: Swift.String

        /// Creates an upstream ancestry record.
        public init(repository: Swift.String, commit: Swift.String) {
            self.repository = repository
            self.commit = commit
        }
    }
}
