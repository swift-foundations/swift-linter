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

public import Manifest_Executable

extension Lint.SingleFile {
    /// A SwiftPM package dependency parsed from a consumer's
    /// `Lint.swift` `dependencies:` argument.
    ///
    /// Thread I collapses this name to a typealias for
    /// ``Manifest/Executable/PackageDependency``. The underlying type
    /// lives in `swift-manifests`'s `Manifest Executable` module so it
    /// is shared across single-file consumer-manifest tools (this
    /// linter; future formatter, doc generator, etc.). The Lint-
    /// specific Extractor in ``Lint/SingleFile/Extractor`` continues
    /// to produce values of this type from the consumer's parsed
    /// Swift literal; the materialize-and-spawn pipeline consumes
    /// them via ``Manifest/Executable/dispatch(configuration:)``.
    public typealias PackageDependency = Manifest.Executable.PackageDependency
}
