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
    /// Errors raised by the single-file (Shape γ) dispatch path.
    public enum Error: Swift.Error, Swift.Sendable {
        /// The consumer's `Lint.swift` could not be read from disk.
        case readFailed(path: Swift.String, description: Swift.String)

        /// The `// swift-linter-tools-version:` magic-comment header
        /// was absent. Detection should have caught this — emitting
        /// the error explicitly aids debugging when dispatch is
        /// invoked directly.
        case missingToolsVersion(path: Swift.String)

        /// SwiftSyntax parsing of the consumer's `Lint.swift` failed
        /// or surfaced syntax errors that prevent dep extraction.
        case parseFailed(path: Swift.String, description: Swift.String)

        /// The dep extractor could not find a top-level
        /// `Lint.run(dependencies: [...]) { ... }` call expression,
        /// or the `dependencies:` argument was not a literal array
        /// of `.package(...)` calls.
        case dependenciesNotFound(path: Swift.String, description: Swift.String)

        /// A `.package(...)` call inside the `dependencies:` array
        /// had an unrecognized argument shape (e.g., missing `path:`
        /// or `url:`, missing `products:`).
        case malformedPackageCall(path: Swift.String, description: Swift.String)

        /// Materialization of the eval project on disk failed
        /// (directory creation, file write, or PackageDescription
        /// rendering).
        case materializationFailed(reason: Swift.String)

        /// `swift run --package-path <eval> Lint` could not be
        /// spawned (binary not found, permission denied, fork failure).
        case spawnFailed(consumerPackageRoot: Swift.String, description: Swift.String)
    }
}
