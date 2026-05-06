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

internal import Environment
internal import File_System
internal import Manifest
internal import URI_Standard

/// Detects and evaluates a consumer's `Lint.swift` configuration
/// file via the ``Manifest/Manifest`` subprocess loader.
///
/// Phase 2 v2 (this file) replaces the v1 detection-only stub with
/// a full single-file evaluator: when `Lint.swift` is present at
/// the consumer's package root, the driver compiles + runs it via
/// `swift-manifest`, captures the typed value as
/// ``Lint/Manifest``, and constructs the runtime
/// ``Lint/Configuration`` from the manifest's enabled rule IDs.
///
/// ## Manifest contract
///
/// A consumer's `Lint.swift` MUST declare a file-scope
/// `let manifest: Lint.Manifest = …` value. The driver shim that
/// `swift-manifest` generates serializes this value as JSON and
/// the parent decodes it back via
/// ``Lint/Manifest/deserialize(_:)``.
///
/// ## Path discovery
///
/// `swift-linter` itself does not know its own filesystem
/// location at runtime. The driver reads the `SWIFT_LINTER_PATH`
/// environment variable to locate the swift-linter source tree
/// (and, by adjacency, sibling foundation packages used in the
/// generated driver shim's deps). When the variable is unset the
/// driver falls back to the workspace-relative default
/// `/Users/coen/Developer/swift-foundations/swift-linter` so that
/// local development verifies without per-shell setup. Production
/// deployments SHOULD set `SWIFT_LINTER_PATH` explicitly.
///
/// ## Failure mode
///
/// If `swift-manifest`'s evaluation fails — manifest absent,
/// driver compile error, runtime trap, JSON decode error — the
/// driver falls back to the v1-default Configuration (every rule
/// in ``Lint/Rule/builtIn`` enabled at default severity). This
/// matches the v1 invariant: the same R5 27-hit count holds even
/// when the v2 evaluation surface is misconfigured.
extension Lint {
    public enum SwiftDriver {}
}

extension Lint.SwiftDriver {
    /// Detects whether a `Lint.swift` exists at the consumer's
    /// package root.
    public static func lintSwiftPath(at consumerPackageRoot: Swift.String) -> Swift.String? {
        let candidate = "\(consumerPackageRoot)/Lint.swift"
        guard let directory = try? File.Directory(validating: consumerPackageRoot) else {
            return nil
        }
        guard let entries = try? directory.entries() else {
            return nil
        }
        for entry in entries where Swift.String(entry.name) == "Lint.swift" {
            return candidate
        }
        return nil
    }

    /// Resolve the configuration for the given consumer root.
    public static func resolveConfiguration(
        consumerPackageRoot: Swift.String
    ) -> Lint.Configuration {
        guard lintSwiftPath(at: consumerPackageRoot) != nil else {
            return _defaultConfiguration()
        }
        do {
            let manifest = try Manifest.load(
                Lint.Manifest.self,
                from: consumerPackageRoot,
                named: "Lint.swift",
                valueName: "manifest",
                dependencies: _manifestDependencies()
            )
            return _configuration(from: manifest)
        } catch {
            return _defaultConfiguration()
        }
    }
}

// MARK: - Parent directive parser

extension Lint.SwiftDriver {
    /// Parse a `// parent: <URL>` directive from the leading
    /// comment lines of a Lint.swift file at `path`.
    ///
    /// Reads the file via swift-file-system, then delegates to
    /// ``_parseParentURLFromContent(_:)``. Reading is best-effort;
    /// any I/O failure returns `nil` without throwing.
    ///
    /// TODO (commit #3.5): replace the hand-rolled scan in
    /// ``_parseParentURLFromContent(_:)`` with a parser-primitive
    /// composition over `Span<UInt8>`, eliminating the intermediate
    /// `Swift.String` allocation and the manual line-splitting
    /// loop. The parser-primitive ecosystem (swift-parser-primitives
    /// + swift-ascii-parser-primitives) provides Skip / Literal /
    /// Take / OneOf / Filter primitives; the deferral isolates the
    /// learning-curve of that API surface from the type-discipline
    /// refactor in this commit.
    internal static func _parseParentURL(at path: File.Path) -> URI? {
        let contents: Swift.String
        do {
            let bytes: [UInt8] = try File(path).read.full { (span: Span<UInt8>) -> [UInt8] in
                var array: [UInt8] = []
                array.reserveCapacity(span.count)
                for i in 0..<span.count { array.append(span[i]) }
                return array
            }
            contents = Swift.String(decoding: bytes, as: UTF8.self)
        } catch {
            return nil
        }
        return _parseParentURLFromContent(contents)
    }

    /// Parse a `// parent: <URL>` directive from a Lint.swift's
    /// source text.
    ///
    /// Inspects up to the first 30 lines (after stripping leading
    /// whitespace) for a directive of the form `// parent: <URL>`.
    /// Only `http://`, `https://`, and `file://` schemes are
    /// accepted. Returns the parsed `URI` if a directive is found
    /// and parses cleanly, otherwise `nil`. Treats absent and
    /// malformed directives identically — the resolver's fall-back
    /// path is the same in both cases.
    internal static func _parseParentURLFromContent(
        _ contents: Swift.String
    ) -> URI? {
        var lineIndex = 0
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            if lineIndex >= 30 { break }
            lineIndex += 1
            var stripped = line
            while let first = stripped.first, first == " " || first == "\t" {
                stripped = stripped.dropFirst()
            }
            guard stripped.hasPrefix("// parent:") else { continue }
            var rest = stripped.dropFirst("// parent:".count)
            while let first = rest.first, first == " " || first == "\t" {
                rest = rest.dropFirst()
            }
            let urlEnd = rest.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "\r" })
                ?? rest.endIndex
            let urlString = Swift.String(rest[rest.startIndex..<urlEnd])
            guard urlString.hasPrefix("http://")
                    || urlString.hasPrefix("https://")
                    || urlString.hasPrefix("file://")
            else { continue }
            // Validate the URL parses as RFC 3986 via swift-uri-standard.
            // Malformed URLs are silently skipped (treated as absent
            // directive); the resolver's fall-back handles consumer-only
            // configuration the same way.
            let uri: URI
            do {
                uri = try URI(urlString)
            } catch {
                continue
            }
            return uri
        }
        return nil
    }
}

// MARK: - Internal helpers

extension Lint.SwiftDriver {
    /// Default Configuration: every built-in rule enabled at its
    /// default severity. Identical to v1 detection-only behavior.
    internal static func _defaultConfiguration() -> Lint.Configuration {
        Lint.Configuration(rules: {
            for rule in Lint.Rule.builtIn {
                Lint.Rule.Configuration.enable(type(of: rule))
            }
        })
    }

    /// Build a runtime Configuration from a parsed manifest by
    /// looking up each rule ID in ``Lint/Rule/builtIn``. Unknown
    /// rule IDs are silently ignored at v2 (rule registration is
    /// not yet pluggable from the manifest); known IDs are enabled
    /// at the rule's default severity.
    ///
    /// `disabledRuleIDs` are not honored by this single-tier helper;
    /// the multi-tier resolver in commit #3 routes through a
    /// `_configuration(from:parent:)` overload that translates
    /// disabled IDs to `Lint.Rule.Configuration.disable(...)` entries.
    internal static func _configuration(from manifest: Lint.Manifest) -> Lint.Configuration {
        let enabled = Set(manifest.enabledRuleIDs)
        return Lint.Configuration(rules: {
            for rule in Lint.Rule.builtIn {
                let ruleID = type(of: rule).id
                if enabled.contains(ruleID) {
                    Lint.Rule.Configuration.enable(type(of: rule))
                }
            }
        }, excluded: manifest.excludedPaths)
    }

    /// The dependency set the driver shim compiles against.
    ///
    /// Derived from `SWIFT_LINTER_PATH` (or the workspace default).
    /// The shim needs:
    ///
    ///   - `JSON` (for `.jsonString()` on the typed value),
    ///   - `File_System` (for the `File.write.atomic` output sink),
    ///   - `Linter` (for the ``Lint/Manifest`` type).
    internal static func _manifestDependencies() -> [Manifest.Dependency] {
        let linterPath = Environment.read("SWIFT_LINTER_PATH")
            ?? "/Users/coen/Developer/swift-foundations/swift-linter"
        let workspace = linterPath + "/.."
        return [
            Manifest.Dependency(
                path: workspace + "/swift-json",
                packageName: "swift-json",
                product: "JSON",
                imports: ["JSON"]
            ),
            Manifest.Dependency(
                path: workspace + "/swift-file-system",
                packageName: "swift-file-system",
                product: "File System",
                imports: ["File_System"]
            ),
            Manifest.Dependency(
                path: linterPath,
                packageName: "swift-linter",
                product: "Linter",
                imports: ["Linter"]
            )
        ]
    }
}
