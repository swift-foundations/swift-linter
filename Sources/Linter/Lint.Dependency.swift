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

@_exported public import File_System
@_exported public import Package_Primitives
@_exported public import URI_Standard_Library_Integration
@_exported public import Version_Primitives_Standard_Library_Integration

/// A SwiftPM dependency declared at the consumer's `Lint.swift` call site.
///
/// `Lint.Dependency` values appear in the `dependencies:` argument of
/// ``Lint/run(dependencies:configuration:)``. The values are consumed
/// syntactically at phase 1 (AST extraction by swift-linter) to generate
/// the eval-project's `Package.swift`; at phase 2 (Swift compile + run of
/// the eval project) the values pass through unused — the deps they
/// describe are already SwiftPM-resolved.
///
/// Construct via the static factories:
///
/// ```swift
/// Lint.Dependency.package(
///     path: "../../swift-primitives-linter-rules",
///     products: ["Linter Primitives Rules"]
/// )
///
/// Lint.Dependency.package(
///     url: "https://github.com/example/swift-foo.git",
///     from: "1.0.0",
///     products: ["Foo"]
/// )
///
/// Lint.Dependency.package(
///     url: "https://github.com/swiftlang/swift-syntax.git",
///     "602.0.0"..<"603.0.0",
///     products: ["SwiftSyntax"]
/// )
/// ```
///
/// Each typed primitive carries a string-literal conformance via its
/// Standard Library Integration target, so consumer call sites stay
/// literal-shaped while the type system carries domain identity:
/// `File.Path`, `URI`, `Version.Semantic`, `Version.Range<Version.Semantic>`,
/// `Product.Name`.
extension Lint {
    public struct Dependency: Swift.Sendable {
        public let kind: Kind
        public let products: [Product.Name]

        public enum Kind: Swift.Sendable {
            case path(File_System.File.Path)
            case url(URI, from: Version.Semantic)
            case urlRange(URI, Version.Range<Version.Semantic>)
        }

        public init(kind: Kind, products: [Product.Name]) {
            self.kind = kind
            self.products = products
        }

        /// A path-based SwiftPM dependency.
        ///
        /// `path` is resolved relative to the generated eval project's
        /// `Package.swift`. The eval project sits at
        /// `<consumerRoot>/.swift-lint/eval/Package.swift`, so paths
        /// must be expressed relative to that location (typically two
        /// levels deeper than the consumer's own `Package.swift`).
        public static func package(
            path: File_System.File.Path,
            products: [Product.Name]
        ) -> Lint.Dependency {
            Lint.Dependency(kind: .path(path), products: products)
        }

        /// A URL-based SwiftPM dependency with `from: "X.Y.Z"` version range.
        public static func package(
            url: URI,
            from version: Version.Semantic,
            products: [Product.Name]
        ) -> Lint.Dependency {
            Lint.Dependency(kind: .url(url, from: version), products: products)
        }

        /// A URL-based SwiftPM dependency with an explicit `lower..<upper`
        /// version range.
        ///
        /// Consumers express the range as a half-open
        /// `Swift.Range<Version.Semantic>`; the stored shape is
        /// `Version.Range<Version.Semantic>` with `.inclusive(lower)` /
        /// `.exclusive(upper)` bounds — matching SwiftPM's canonical
        /// `lower..<upper` semantics.
        public static func package(
            url: URI,
            _ range: Swift.Range<Version.Semantic>,
            products: [Product.Name]
        ) -> Lint.Dependency {
            let typedRange = Version.Range<Version.Semantic>(
                lowerBound: .inclusive(range.lowerBound),
                upperBound: .exclusive(range.upperBound)
            )
            return Lint.Dependency(kind: .urlRange(url, typedRange), products: products)
        }
    }
}
