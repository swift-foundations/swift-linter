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

extension Lint.SingleFile {
    /// A SwiftPM package dependency parsed from a consumer's
    /// `Lint.swift` `dependencies:` argument.
    ///
    /// Carries one logical `.package(...)` clause and the list of
    /// products required from that package. The materializer renders
    /// one `.package(...)` line per unique entry plus one
    /// `.product(name:package:)` line per product on the eval
    /// target's `dependencies` list.
    ///
    /// This type is internal to the single-file dispatch path —
    /// callers express dependencies via the consumer-facing
    /// ``Lint/Dependency`` value type in the `Linter` product. The
    /// extractor in ``Lint/SingleFile/Extractor`` produces this
    /// resolved form from the consumer's parsed Swift literal.
    public struct PackageDependency: Swift.Sendable, Swift.Hashable {
        public enum Source: Swift.Sendable, Swift.Hashable {
            case path(Swift.String)
            case urlFrom(url: Swift.String, from: Swift.String)
            case urlRange(url: Swift.String, lower: Swift.String, upper: Swift.String)
        }

        /// The package source: filesystem path or git URL with version constraint.
        public let source: Source

        /// SwiftPM package name (derived from path/URL basename).
        public let name: Swift.String

        /// Products to depend on from this package.
        public let products: [Swift.String]

        public init(source: Source, name: Swift.String, products: [Swift.String]) {
            self.source = source
            self.name = name
            self.products = products
        }
    }
}
