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
internal import JSON
internal import Linter_Primitives

extension Lint {
    /// Engine-side discovery of the owning SwiftPM package for a source
    /// file, with per-package caching of the package's declared
    /// brand-newtype names.
    ///
    /// ## Why
    ///
    /// Recognizer-class rules (PATTERN-017 / CONV-016 / IMPL-010) name
    /// the firing class "same-package implementation of a brand
    /// newtype" as legitimate-by-construction in their rule prose but
    /// cannot identify it from the AST alone — the SwiftPM-package
    /// boundary lives a level of context the visitor doesn't have.
    /// This type computes that context for each file the engine
    /// touches and threads it onto every parsed source via the
    /// ``Lint/Source/Parsed/brandTypes`` field.
    ///
    /// See
    /// `swift-foundations/swift-linter-rules/Research/numerics-rule-recognizer-2026-05-12.md`
    /// for the Option (1) recommendation.
    ///
    /// ## How
    ///
    /// 1. Walk up the directory tree from each linted file looking
    ///    for a `Package.swift` sibling.
    /// 2. If found, look for a `.swift-linter.json` adjacent to it.
    /// 3. Parse + validate the JSON (top-level `brandTypes` string
    ///    array; unknown keys are an error per the schema's
    ///    `additionalProperties: false`).
    /// 4. Cache the resolved `(packageRoot, brandTypes)` so subsequent
    ///    files in the same package skip the walk and the I/O.
    ///
    /// The cache lives for the duration of a lint run — the engine
    /// owns one ``Brands`` value and threads it through the parsed-
    /// source resolver.
    public struct Brands: Sendable {
        /// One cache entry per discovered package root. `nil` means
        /// "package found but no `.swift-linter.json`"; an absent key
        /// means "not yet discovered."
        internal var cache: [Swift.String: Swift.Set<Swift.String>] = [:]

        /// Files for which discovery already ran. We record the result
        /// (which package root, if any, owns the file) so repeated
        /// queries are O(1) after the first.
        internal var fileToPackage: [Swift.String: Swift.String?] = [:]

        public init() {}

        /// Returns the set of brand-newtype names declared by the
        /// SwiftPM package that owns the file at `filePath`.
        ///
        /// Returns the empty set when:
        ///   - the file is not inside a SwiftPM package, OR
        ///   - the owning package has no `.swift-linter.json`, OR
        ///   - the `.swift-linter.json` declares an empty
        ///     `brandTypes` list.
        ///
        /// Throws on schema-validation failure — the engine surfaces
        /// this to the caller; in CLI mode it becomes a clear error
        /// rather than a silent ignore-typo.
        ///
        /// - Parameter filePath: absolute path string for the source
        ///   file being linted (`Lint.Source.File.filePath`).
        public mutating func brandTypes(forFile filePath: Swift.String) throws(Error) -> Swift.Set<Swift.String> {
            if let cachedPackage = fileToPackage[filePath] {
                guard let root = cachedPackage else { return [] }
                return cache[root] ?? []
            }
            guard let packageRoot = Self.discoverPackageRoot(forFile: filePath) else {
                fileToPackage[filePath] = .some(.none)
                return []
            }
            fileToPackage[filePath] = .some(.some(packageRoot))
            if let cached = cache[packageRoot] {
                return cached
            }
            let resolved = try Self.loadBrandTypes(packageRoot: packageRoot)
            cache[packageRoot] = resolved
            return resolved
        }

        /// Errors surfaced by brand-type discovery.
        ///
        /// All variants carry the offending package path so the user
        /// can fix the typo in the right file.
        public enum Error: Swift.Error, Sendable, Hashable {
            /// `.swift-linter.json` exists but its bytes are not valid
            /// UTF-8 or not valid JSON.
            case invalidJSON(packagePath: Swift.String, reason: Swift.String)

            /// Top-level value is not a JSON object.
            case notAnObject(packagePath: Swift.String)

            /// An unknown top-level key is present. Per the schema's
            /// `additionalProperties: false`, this is a typo and
            /// rejected so the user sees the error fast.
            case unknownKey(packagePath: Swift.String, key: Swift.String)

            /// `brandTypes` is present but is not a JSON array of
            /// strings.
            case invalidBrandTypes(packagePath: Swift.String, reason: Swift.String)
        }
    }
}

// MARK: - Discovery

extension Lint.Brands {
    /// Walks up the directory tree from `filePath` looking for the
    /// first ancestor directory that contains a `Package.swift`.
    /// Returns the absolute path of that directory (the package
    /// root), or `nil` if no `Package.swift` is found.
    ///
    /// The walk operates on `File.Path` parents, so it bottoms out
    /// naturally at filesystem root.
    internal static func discoverPackageRoot(forFile filePathString: Swift.String) -> Swift.String? {
        guard let path = try? File.Path(filePathString) else { return nil }
        var current: File.Path? = path.parent
        while let directory = current {
            let candidate = directory.description.hasSuffix("/")
                ? directory.description + "Package.swift"
                : directory.description + "/Package.swift"
            guard let candidatePath = try? File.Path(candidate) else {
                current = directory.parent
                continue
            }
            let candidateFile = File(candidatePath)
            if candidateFile.stat.exists {
                return directory.description
            }
            current = directory.parent
        }
        return nil
    }

    /// Reads `<packageRoot>/.swift-linter.json` (if present), parses
    /// it, and extracts the `brandTypes` field.
    ///
    /// Returns the empty set when the file is absent. Throws
    /// ``Error/invalidJSON``, ``Error/notAnObject``,
    /// ``Error/unknownKey``, or ``Error/invalidBrandTypes`` when the
    /// file is present but malformed.
    internal static func loadBrandTypes(packageRoot: Swift.String) throws(Error) -> Swift.Set<Swift.String> {
        let separator = packageRoot.hasSuffix("/") ? "" : "/"
        let configPath = packageRoot + separator + ".swift-linter.json"
        guard let path = try? File.Path(configPath) else { return [] }
        let file = File(path)
        guard file.stat.exists else { return [] }
        let bytes: [Swift.UInt8]
        do {
            bytes = try file.read.full { (span: Span<Swift.UInt8>) in
                var copy: [Swift.UInt8] = []
                copy.reserveCapacity(span.count)
                for i in 0..<span.count {
                    copy.append(span[i])
                }
                return copy
            }
        } catch {
            throw .invalidJSON(packagePath: packageRoot, reason: "unreadable: \(error)")
        }
        let json: JSON
        do {
            json = try JSON.parse(bytes)
        } catch {
            throw .invalidJSON(packagePath: packageRoot, reason: "\(error)")
        }
        return try Self.extractBrandTypes(json: json, packagePath: packageRoot)
    }

    /// Validates the parsed JSON against the schema and extracts the
    /// `brandTypes` set.
    ///
    /// Hand-coded validator mirroring
    /// `Schemas/swift-linter-v1.json`. The schema is the canonical
    /// contract; this code MUST stay in sync with it. Recognized
    /// top-level keys: `$schema`, `brandTypes`. Any other key throws
    /// ``Error/unknownKey``.
    internal static func extractBrandTypes(
        json: JSON,
        packagePath: Swift.String
    ) throws(Error) -> Swift.Set<Swift.String> {
        guard let members = json.object else {
            throw .notAnObject(packagePath: packagePath)
        }
        let knownKeys: Swift.Set<Swift.String> = ["$schema", "brandTypes"]
        for (key, _) in members {
            guard knownKeys.contains(key) else {
                throw .unknownKey(packagePath: packagePath, key: key)
            }
        }
        guard let brandsValue = members.first(where: { $0.key == "brandTypes" })?.value else {
            // `brandTypes` is required by the schema; absence is
            // either a legitimate empty config (the file declares only
            // `$schema`) or a typo we already rejected via the
            // unknown-key check. Treat absence as an empty brand set
            // — back-compat with `{}` configs.
            return []
        }
        guard let array = brandsValue.array else {
            throw .invalidBrandTypes(packagePath: packagePath, reason: "expected array")
        }
        var result: Swift.Set<Swift.String> = []
        for element in array {
            do {
                let value = try Swift.String(json: element)
                result.insert(value)
            } catch {
                throw .invalidBrandTypes(
                    packagePath: packagePath,
                    reason: "expected string array element"
                )
            }
        }
        return result
    }
}
