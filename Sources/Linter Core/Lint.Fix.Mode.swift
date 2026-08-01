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

extension Lint.Fix {
    /// Whether a fix run writes its rewrites or only reports them.
    ///
    /// The two modes run the identical rewriter pipeline and differ in
    /// exactly one statement — the write. A dry run that took a different
    /// path through the engine would be a preview of something other than
    /// what applying does, which is the one property this flag exists to
    /// provide.
    public enum Mode: Swift.String, Sendable, Hashable, CaseIterable {
        /// Compute the rewrites and write them over the source files.
        case apply

        /// Compute the rewrites and report them, changing nothing on disk.
        case dryRun = "dry-run"
    }
}
