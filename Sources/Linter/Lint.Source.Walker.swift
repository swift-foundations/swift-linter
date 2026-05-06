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

public import Foundation

/// Recursively walks a directory, returning Swift source paths for linting.
///
/// Standard exclusions: `.build/`, `Carthage/`, `Pods/`, `*.docc/Resources/`,
/// `.swiftpm/`, `.benchmarks/`. Hidden directories are skipped to avoid
/// traversing `.git`.
extension Lint.Source {
    public enum Walker {}
}

extension Lint.Source.Walker {
    public static func swiftSourcePaths(under root: Swift.String) -> [Swift.String] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            return root.hasSuffix(".swift") ? [root] : []
        }
        let url = URL(fileURLWithPath: root)
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var results: [Swift.String] = []
        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            if isExcluded(path: path) {
                if isDirectoryURL(fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard !isDirectoryURL(fileURL), path.hasSuffix(".swift") else { continue }
            results.append(path)
        }
        return results.sorted()
    }

    static func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static let exclusions: [Swift.String] = [
        "/.build/", "/Carthage/", "/Pods/",
        ".docc/Resources/",
        "/.swiftpm/", "/.benchmarks/",
        "/DerivedData/",
    ]

    static func isExcluded(path: Swift.String) -> Bool {
        exclusions.contains(where: path.contains)
    }
}
