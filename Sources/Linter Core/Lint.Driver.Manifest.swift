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

// Lint.Driver.Manifest — the driver's manifest-detection namespace, distinct
// from the serializable `Lint.Manifest` value type.
extension Lint.Driver {
    /// Namespace for consumer `Lint.swift` manifest-file detection.
    public enum Manifest {}
}

extension Lint.Driver.Manifest {
    /// Detects whether a `Lint.swift` exists at the consumer's
    /// package root.
    ///
    /// F-A2.2 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
    /// typed `File.Path` on both parameter and return.
    public static func path(at consumerPackageRoot: File.Path) -> File.Path? {
        let candidate: File.Path = consumerPackageRoot / "Lint.swift"
        // Single typed existence query (see Lint.File.Single.Detection.detect
        // for the same collapse of a directory-enumeration reinvention).
        return File.System.Stat.isFile(at: candidate) ? candidate : nil
    }
}
