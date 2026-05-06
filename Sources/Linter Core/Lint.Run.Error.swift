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

public import URI_Standard

extension Lint.Run {
    public enum Error: Swift.Error, Hashable, Sendable {
        case fileNotReadable(path: Swift.String)
        case nonUTF8(path: Swift.String)

        /// A `// parent: <URL>` directive's URL fetch failed (curl
        /// non-zero exit). `exitCode` is the curl exit code; `stderr`
        /// is empty in v2 (`Process.Stream` supports only `.inherit`,
        /// so curl's diagnostic message goes to the parent's stderr
        /// directly and is not captured). The driver catches this
        /// error and falls back to the consumer-only Configuration
        /// per the supervisor block; never propagates to the lint run.
        case parentFetchFailed(url: URI, exitCode: Int32, stderr: Swift.String)

        /// A cycle was detected in the parent chain. `visited` is
        /// the parent-first traversal up to the cycle point;
        /// `at` is the URI whose revisit closed the cycle.
        case parentChainCycle(visited: [URI], at: URI)

        /// The parent chain exceeded the depth-16 sanity backstop
        /// without revisiting any URI (i.e., not a cycle).
        case parentChainTooDeep(depth: Int)
    }
}
