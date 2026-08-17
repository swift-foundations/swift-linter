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

// `description` on a path is declared by `Paths`, the primitive module
// `File_System` builds on; member-import visibility requires naming it
// here rather than relying on the re-export.
internal import Paths

extension Lint.Fix.Change {
    /// A unified-style diff of this change, as text.
    ///
    /// Rendered here rather than shelled out to `diff(1)`: a fix run must
    /// produce the same preview on every platform the engine ships for, and
    /// on a machine holding no diff utility at all.
    ///
    /// The algorithm is deliberately the simple one — common prefix, common
    /// suffix, one hunk for the middle. Rewrites from a syntax-directed fix
    /// are localized by construction, so the cheap shape produces the same
    /// reading as a full longest-common-subsequence for the input this
    /// actually gets, and an occasional wide hunk is a far better failure
    /// than an engine carrying a diff implementation nobody reviews.
    public var diff: Swift.String {
        let before: [Swift.Substring] = original.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        let after: [Swift.Substring] = fixed.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < (before.count - prefix),
            suffix < (after.count - prefix),
            before[before.count - 1 - suffix] == after[after.count - 1 - suffix]
        {
            suffix += 1
        }

        let removed = before[prefix..<(before.count - suffix)]
        let added = after[prefix..<(after.count - suffix)]

        var lines: [Swift.String] = []
        lines.append("--- \(path.description)")
        lines.append("+++ \(path.description)")
        lines.append(
            "@@ -\(prefix + 1),\(removed.count) +\(prefix + 1),\(added.count) @@"
                + (rules.isEmpty ? "" : " " + rules.map(\.description).joined(separator: ", "))
        )
        for line in removed { lines.append("-\(line)") }
        for line in added { lines.append("+\(line)") }
        return lines.joined(separator: "\n") + "\n"
    }
}
