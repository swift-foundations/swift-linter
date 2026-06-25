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

extension Lint.File.Single.Channel {
    /// Errors raised by a ``Channel``'s ``Channel/write(_:consumerPackageRoot:nonce:)``
    /// and ``Channel/read()``.
    ///
    /// The read-side cases (``invalidPath`` / ``unreadable`` / ``unparseable``)
    /// fire ONLY when the channel's environment variable is SET — a set-but-
    /// broken manifest is a hard failure, never a silent fall-through to the
    /// unmodified configuration. Distinguishing them keeps the diagnostic
    /// precise about which stage failed.
    public enum Error: Swift.Error, Swift.Sendable {
        /// The channel's variable was SET but its value was not a valid path.
        case invalidPath(variable: Swift.String, raw: Swift.String, description: Swift.String)

        /// The channel's variable was SET but the file could not be read.
        case unreadable(variable: Swift.String, path: File.Path, description: Swift.String)

        /// The channel's variable was SET but the file did not parse as JSON or
        /// deserialize as a `Lint.Manifest`.
        case unparseable(variable: Swift.String, path: File.Path, description: Swift.String)

        /// Writing the manifest failed (directory creation or atomic write).
        case writeFailed(variable: Swift.String, description: Swift.String)
    }
}
