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

public import Paths
public import SPM_Standard
public import URI_Standard
public import URI_Standard_Library_Integration

// Re-export the `Version.Semantic: ExpressibleByStringLiteral` conformance to
// the consumer's `Lint.swift` scope. Under SE-0444 `MemberImportVisibility`,
// the eval-project target sees only the members of modules it imports
// directly OR `@_exported` from those imports. Plain `public import` of
// `SPM_Standard` (above) does NOT propagate member visibility for SPM_Standard's
// `@_exported` chain; the OLD `Lint.Dependency.swift` carried the SLI
// re-exports directly via `@_exported`, so the deletion in commit 2fb5c42
// silently took the conformance off the eval-project's member-lookup table.
// The carrier-canary surfaced this as `init(stringLiteral:)` unavailable on
// the `"602.0.0"..<"603.0.0"` operands required by `package(url:_:products:)`.
@_exported public import Version_Primitives_Standard_Library_Integration

// Linter-convention static factories on `Package.Dependency` that mirror
// SwiftPM's `PackageDescription.Package.Dependency.package(...)` call-site
// shape. These exist solely to give consumer `Lint.swift` files a PackageDescription-
// mirroring dependency DSL without making the value-level `Package.Dependency`
// type at swift-spm-standard re-acquire the string-form factories the v0.4
// typed-Source-variants change retired.
//
// The factories are pure construction helpers: they derive a typed
// `Package.Name` from the path basename or URL last path segment (mirroring
// the same derivation `Lint.File.Single.Extractor.parsePackageCall(...)`
// performs at AST extraction time), wrap the typed `Paths.Path` / `URI`
// inside the appropriate `Package.Dependency.Source` case, and forward
// the consumer-supplied product list.
//
// These are NOT appropriate for general `Package.Dependency` construction
// (which should use the typed `init(source:name:products:)` directly so
// the consumer authors the typed `Package.Name`). They are a linter-domain
// affordance — see `Lint.run(dependencies:rules:)` for the entry point
// that consumes the resulting array.

extension Package.Dependency {

    // MARK: - Path form

    /// `.package(path:..., products:)` factory — sibling-disk dependency.
    ///
    /// The `name:` of the produced `Package.Dependency` is derived from
    /// the path's last component (e.g., `"../swift-foo-primitives"` →
    /// `Package.Name("swift-foo-primitives")`), mirroring the AST
    /// extractor's `Self.name(at:consumerPackageRoot:)` derivation at
    /// `Lint.File.Single.Extractor.swift`.
    ///
    /// Crashes on a malformed path string via the `Paths.Path`
    /// `ExpressibleByStringLiteral` conformance's trap on validation
    /// failure (empty, control characters, or interior NUL). At eval-
    /// project compile-time the same string has already passed
    /// extraction's typed validation, so the trap is defense-in-depth.
    @inlinable
    public static func package(
        path: Swift.String,
        products: [Product.Name]
    ) -> Package.Dependency {
        let basename: Swift.String = path.split(separator: "/").last.map(Swift.String.init) ?? path
        return Package.Dependency(
            source: .path(Paths.Path(stringLiteral: path)),
            name: Package.Name(_unchecked: basename),
            products: products
        )
    }

    // MARK: - URL form (positional range requirement)

    /// `.package(url:_:products:)` factory — git-URL dependency with a
    /// half-open version range. The middle argument is a
    /// `Swift.Range<Version.Semantic>`, matching the OLD
    /// `Lint.Dependency.package(url:_:products:)` interface exactly
    /// so consumer call sites of the form
    /// `"602.0.0"..<"603.0.0"` resolve via the stdlib `..<` operator
    /// (Bound=Version.Semantic via SLI) rather than relying on the
    /// SPM_Standard module-scope `..<` overload to be in operator-
    /// lookup scope under MemberImportVisibility.
    ///
    /// The `name:` is derived from the URL's last path segment, with
    /// any trailing `.git` suffix stripped (e.g.,
    /// `"https://github.com/swiftlang/swift-syntax.git"` →
    /// `Package.Name("swift-syntax")`), mirroring the extractor's
    /// `Self.name(at: urlString)` derivation.
    @inlinable
    public static func package(
        url: Swift.String,
        _ range: Swift.Range<Version.Semantic>,
        products: [Product.Name]
    ) -> Package.Dependency {
        var name: Swift.String = url.split(separator: "/").last.map(Swift.String.init) ?? url
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        let requirement: Package.Requirement = .range(Version.Range(range))
        return Package.Dependency(
            source: .url(URI(stringLiteral: url), requirement),
            name: Package.Name(_unchecked: name),
            products: products
        )
    }

    // MARK: - URL form (`from:` lower-bound requirement)

    /// `.package(url:from:products:)` factory — git-URL dependency with
    /// an open-ended `from:` lower bound. The `Version.Semantic` lifts
    /// from a string literal via swift-version-primitives's
    /// `ExpressibleByStringLiteral` conformance.
    @inlinable
    public static func package(
        url: Swift.String,
        from version: Version.Semantic,
        products: [Product.Name]
    ) -> Package.Dependency {
        var name: Swift.String = url.split(separator: "/").last.map(Swift.String.init) ?? url
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        return Package.Dependency(
            source: .url(URI(stringLiteral: url), .from(version)),
            name: Package.Name(_unchecked: name),
            products: products
        )
    }

    // MARK: - URL form (`branch:` requirement)

    /// `.package(url:branch:products:)` factory — git-URL dependency
    /// pinned to a branch. For untagged intra-Institute deps resolved off
    /// `main` during active development (the ecosystem default while
    /// packages remain unversioned). Mirrors the single-file extractor's
    /// `branch:` form at `Lint.File.Single.Extractor`.
    @inlinable
    public static func package(
        url: Swift.String,
        branch: Swift.String,
        products: [Product.Name]
    ) -> Package.Dependency {
        var name: Swift.String = url.split(separator: "/").last.map(Swift.String.init) ?? url
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        return Package.Dependency(
            source: .url(URI(stringLiteral: url), .branch(branch)),
            name: Package.Name(_unchecked: name),
            products: products
        )
    }
}
