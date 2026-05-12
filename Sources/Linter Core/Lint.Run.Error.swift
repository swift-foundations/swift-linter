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

extension Lint.Run {
    public enum Error: Swift.Error, Hashable, Sendable {
        case fileNotReadable(path: Swift.String)
        case nonUTF8(path: Swift.String)

        /// Engine-side discovery of an enclosing SwiftPM package's
        /// `.swift-linter.json` failed schema validation. The reason
        /// is a textual rendering of the underlying
        /// ``Lint/Brands/Error``; surfaced here so the run-level error
        /// type stays a single sum.
        case invalidLintConfiguration(reason: Swift.String)
    }
}
