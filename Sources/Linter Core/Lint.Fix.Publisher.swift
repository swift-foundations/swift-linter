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

internal import File_System

extension Lint.Fix {
    /// Publishes an already computed whole-file rewrite plan.
    internal enum Publisher {}
}

extension Lint.Fix.Publisher {
    /// Content-guards and atomically replaces each existing file in order.
    ///
    /// A failure reports both the authoritative plan and the exact prefix
    /// already published. Computation and parsing happen before this boundary,
    /// so traversal and rewrite failures can never publish a partial plan.
    internal static func apply(
        _ changes: [Lint.Fix.Change]
    ) throws(Lint.Run.Error) -> [File.Path] {
        let planned = changes.map(\.path)
        var published: [File.Path] = []
        published.reserveCapacity(changes.count)

        for change in changes {
            let current: Swift.String
            do throws(Lint.Run.Error) {
                current = try Lint.Fix.read(change.path)
            } catch {
                throw .fixPublicationFailed(
                    path: change.path,
                    planned: planned,
                    published: published
                )
            }
            guard current.utf8.elementsEqual(change.original.utf8) else {
                throw .staleFixOriginal(
                    path: change.path,
                    planned: planned,
                    published: published
                )
            }
            do throws(File.System.Write.Atomic.Error) {
                try File(change.path).write.atomic(change.fixed)
            } catch {
                throw .fixPublicationFailed(
                    path: change.path,
                    planned: planned,
                    published: published
                )
            }
            published.append(change.path)
        }
        return published
    }
}
