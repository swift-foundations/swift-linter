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
public import Glob_Primitives
import Glob_Primitives_Standard_Library_Integration
public import Linter_Primitives

/// Recursively discovers Swift source files via `swift-file-system`'s
/// glob support (Foundation-clean composition over
/// `swift-glob-primitives`).
///
/// Standard exclusions: `.build/`, `Carthage/`, `Pods/`,
/// `*.docc/**` (entire DocC catalog tree), `.swiftpm/`, `.benchmarks/`,
/// `DerivedData/`.
extension Lint.Source {
    /// Enumerates the Swift source files under a search root, applying the
    /// standard include/exclude glob patterns.
    public enum Walker {}
}

extension Lint.Source.Walker {
    /// Patterns matched against entries in the search root.
    ///
    /// Include: every Swift file at any depth.
    public static let included: [Glob.Pattern] = ["**/*.swift"]

    /// Patterns excluded from the include set.
    ///
    /// Trailing `/**` matches every entry beneath the named directory at
    /// any depth.
    public static let excluded: [Glob.Pattern] = [
        "**/.build/**",
        "**/.swiftpm/**",
        "**/.benchmarks/**",
        "**/DerivedData/**",
        "**/Carthage/**",
        "**/Pods/**",
        "**/*.docc/**",
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
    /// A nested `Package.swift` signals an independent SwiftPM package
    /// — its sources are owned by that package, not by the outer
    /// consumer. The walker treats each nested manifest's parent
    /// directory as the root of a subtree to skip; the nested package
    /// is its own linter consumer and gets invoked independently on
    /// its own root when desired. The consumer's own root Package.swift
    /// (parent equal to `root`) is preserved.
    ///
    /// Single-file root (`root.description.hasSuffix(".swift")`) is the
    /// degenerate case: the walker emits a single empty-string
    /// ``Lint/Source/Path`` and ``Lint/Run/parsedSource(root:relativePath:manager:)``
    /// resolves I/O via `root` directly.
    public static func paths(under root: File.Path) -> [Lint.Source.Path] {
        // F-A1.2 (audit `2026-05-12-typed-primitive-adoption-audit.md`):
        // single-file degenerate case keyed on the path's extension —
        // ask the typed primitive, not the raw description.
        if root.components.last?.extension?.string == "swift" {
            return [Lint.Source.Path("")]
        }

        let directory = File.Directory(root)
        let files: [File]
        do throws(Glob.Error) {
            files = try directory.glob.files(
                include: included,
                excluding: excluded
            )
        } catch {
            return []
        }

        // Discover nested Package.swift manifests. Glob's `**/*.swift`
        // include pattern picks them up alongside ordinary source files;
        // each manifest with a parent distinct from `root` marks an
        // independent package whose subtree must not be linted as part
        // of the outer consumer.
        var nestedPackageRoots: [File.Path] = []
        for file in files {
            guard file.path.components.last?.string == "Package.swift",
                let parent = file.path.parent,
                parent != root
            else { continue }
            nestedPackageRoots.append(parent)
        }

        // F-A1.1: prior shape manually normalized a trailing slash on
        // `rootString` and used `hasPrefix` + `dropFirst(count)` to
        // derive the relative remainder. `Paths.Path.relative(to:)`
        // owns both prefix-match and remainder construction in one
        // pass (component-level comparison, no separator arithmetic).
        var results: [Lint.Source.Path] = []
        results.reserveCapacity(files.count)
        for file in files {
            if nestedPackageRoots.contains(where: { file.path.hasPrefix($0) }) {
                continue
            }
            guard let relative = file.path.relative(to: root) else {
                continue
            }
            results.append(Lint.Source.Path(relative.string))
        }
        return results.sorted(by: { $0.underlying < $1.underlying })
    }
}
