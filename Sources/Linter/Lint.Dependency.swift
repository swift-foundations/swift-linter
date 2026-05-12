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
/// ```
extension Lint {
    public struct Dependency: Swift.Sendable {
        public let kind: Kind
        public let products: [Swift.String]

        public enum Kind: Swift.Sendable {
            case path(Swift.String)
            case url(Swift.String, from: Swift.String)
            case urlRange(Swift.String, Swift.String, Swift.String)
        }

        public init(kind: Kind, products: [Swift.String]) {
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
            path: Swift.String,
            products: [Swift.String]
        ) -> Lint.Dependency {
            Lint.Dependency(kind: .path(path), products: products)
        }

        /// A URL-based SwiftPM dependency with `from: "X.Y.Z"` version range.
        public static func package(
            url: Swift.String,
            from version: Swift.String,
            products: [Swift.String]
        ) -> Lint.Dependency {
            Lint.Dependency(kind: .url(url, from: version), products: products)
        }

        /// A URL-based SwiftPM dependency with an explicit `lower..<upper`
        /// version range.
        public static func package(
            url: Swift.String,
            _ lower: Swift.String,
            _ upper: Swift.String,
            products: [Swift.String]
        ) -> Lint.Dependency {
            Lint.Dependency(kind: .urlRange(url, lower, upper), products: products)
        }
    }
}
