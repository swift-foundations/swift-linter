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

/// Recursively discovers Swift source files via `swift-file-system`'s
/// glob support (Foundation-clean composition over
/// `swift-glob-primitives`).
///
/// Standard exclusions: `.build/`, `Carthage/`, `Pods/`,
/// `*.docc/Resources/`, `.swiftpm/`, `.benchmarks/`, `DerivedData/`.
extension Lint.Source {
    public enum Walker {}
}

extension Lint.Source.Walker {
    /// Patterns matched against entries in the search root.
    ///
    /// Include: every Swift file at any depth.
    public static let includePatterns: [Swift.String] = [
        "**/*.swift",
    ]

    /// Patterns excluded from the include set.
    ///
    /// Trailing `/**` matches every entry beneath the named directory at
    /// any depth.
    public static let excludePatterns: [Swift.String] = [
        "**/.build/**",
        "**/.swiftpm/**",
        "**/.benchmarks/**",
        "**/DerivedData/**",
        "**/Carthage/**",
        "**/Pods/**",
        "**/*.docc/Resources/**",
    ]

    public static func swiftSourcePaths(under root: Swift.String) -> [Swift.String] {
        // Single-file root: short-circuit; glob-on-file is degenerate.
        if root.hasSuffix(".swift"), let _ = try? File.Path(root) {
            return [root]
        }
        guard let directory = try? File.Directory(validating: root) else {
            return []
        }
        guard let files = try? directory.glob.files(
            include: includePatterns,
            excluding: excludePatterns
        ) else {
            return []
        }
        return files
            .map { Swift.String($0.path) }
            .sorted()
    }
}
