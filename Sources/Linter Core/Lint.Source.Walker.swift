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

    /// Walks the directory at `root` and emits run-root-relative typed
    /// source paths for every Swift file discovered.
    ///
    /// Glob returns absolute paths; the walker strips `root`'s prefix
    /// before emitting so that downstream filter prefixes
    /// (``Lint/Path/Filter/Prefix``) align with the same root-relative
    /// shape (e.g., `"Sources/A/x.swift"` matches prefix `"Sources/A"`
    /// without absolute-path concatenation at call sites).
    ///
    /// Single-file root (`root.description.hasSuffix(".swift")`) is the
    /// degenerate case: the walker emits a single empty-string
    /// ``Lint/Source/Path`` and ``Lint/Run/parsedSource(root:relativePath:manager:)``
    /// resolves I/O via `root` directly.
    public static func swiftSourcePaths(under root: File.Path) -> [Lint.Source.Path] {
        let rootString = root.description

        if rootString.hasSuffix(".swift") {
            return [Lint.Source.Path("")]
        }

        let directory = File.Directory(root)
        guard let files = try? directory.glob.files(
            include: includePatterns,
            excluding: excludePatterns
        ) else {
            return []
        }

        let normalizedRoot = rootString.hasSuffix("/") ? rootString : rootString + "/"
        var results: [Lint.Source.Path] = []
        results.reserveCapacity(files.count)
        for file in files {
            let absolute = file.path.description
            guard absolute.hasPrefix(normalizedRoot) else {
                continue
            }
            let relative = Swift.String(absolute.dropFirst(normalizedRoot.count))
            results.append(Lint.Source.Path(relative))
        }
        return results.sorted(by: { $0.underlying < $1.underlying })
    }
}
