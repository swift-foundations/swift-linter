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
        let directory: File.Directory
        do throws(Paths.Path.Error) {
            directory = try File.Directory(validating: consumerPackageRoot.string)
        } catch {
            return nil
        }
        let entries: [File.Directory.Entry]
        do throws(File.Directory.Contents.Error) {
            entries = try directory.entries()
        } catch {
            return nil
        }
        for entry in entries where Swift.String(entry.name) == "Lint.swift" {
            return candidate
        }
        return nil
    }
}
