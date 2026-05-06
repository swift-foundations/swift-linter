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
internal import Process
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
    ///
    /// Walks the parent chain starting from the consumer's
    /// `Lint.swift` (if present), then folds each layer's
    /// ``Lint/Manifest`` into a layered ``Lint/Configuration`` via
    /// `inheriting:` parent. Layer override semantics live in
    /// ``Lint/Configuration/effectiveRules()``.
    ///
    /// Fall-back paths (per supervisor block entry #5):
    /// - No `Lint.swift` at consumer root → defaults-everything.
    /// - Consumer's `Lint.swift` evaluation fails → defaults-everything.
    /// - Any parent fetch / eval / cycle / depth failure → emit a
    ///   warning, drop the parent chain, return consumer-only
    ///   Configuration.
    public static func resolveConfiguration(
        consumerPackageRoot: Swift.String
    ) -> Lint.Configuration {
        guard let consumerLintPathString = lintSwiftPath(at: consumerPackageRoot) else {
            return _defaultConfiguration()
        }
        // Boundary conversion: lintSwiftPath returns the legacy
        // Swift.String; _parseParentURL takes the typed File.Path.
        let consumerLintPath: File.Path
        do {
            consumerLintPath = try File.Path(consumerLintPathString)
        } catch {
            return _defaultConfiguration()
        }
        let consumerManifest: Lint.Manifest
        do {
            consumerManifest = try Manifest.load(
                Lint.Manifest.self,
                from: consumerPackageRoot,
                named: "Lint.swift",
                valueName: "manifest",
                dependencies: _manifestDependencies()
            )
        } catch {
            return _defaultConfiguration()
        }

        // Single-tier path: no `// parent:` directive in consumer's
        // Lint.swift → no parent chain to walk.
        guard let firstParentURI = _parseParentURL(at: consumerLintPath) else {
            return _configuration(from: consumerManifest, parent: nil)
        }

        // Walk parent chain. Per supervisor block entry #5, any
        // failure (fetch, cycle, depth, eval) emits a warning and
        // drops the chain — never propagates to the lint run.
        var parentChain: [Lint.Manifest]
        do {
            parentChain = try _resolveParentChain(rootURL: firstParentURI)
        } catch {
            print("[swift-linter] WARN: parent chain resolution failed: \(error); proceeding with consumer-only configuration.")
            return _configuration(from: consumerManifest, parent: nil)
        }

        // Fold parent chain into Configuration chain (parent-first)
        // then layer the consumer's Configuration on top.
        var current: Lint.Configuration? = nil
        for manifest in parentChain {
            current = _configuration(from: manifest, parent: current)
        }
        return _configuration(from: consumerManifest, parent: current)
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

// MARK: - URL fetch (with per-process memoization)

extension Lint.SwiftDriver {
    /// Fetch the contents of a parent `URI`, memoizing within the
    /// passed-through dictionary.
    ///
    /// Two backends:
    ///
    /// - `file://<path>` — read the local file directly via
    ///   swift-file-system using the URI's typed `path` accessor
    ///   (no manual scheme manipulation; no subprocess overhead).
    /// - `http://`, `https://` — invoke `curl -fsSL <uri.value> -o
    ///   <temp>` via ``Process/Spawn/run(_:)``; read the temp file;
    ///   delete it.
    ///
    /// Memoization is per-process and keyed on the `URI`. Same URI
    /// fetched twice in one chain resolution = one curl invocation.
    /// In a monorepo CI fan-out, this caps each linter process at
    /// O(unique parent URIs) requests rather than O(consumers ×
    /// parents).
    ///
    /// Errors throw ``Lint/Run/Error/parentFetchFailed(url:exitCode:stderr:)``
    /// for HTTP / read failures. The driver's resolver catches and
    /// emits a warning + falls back to consumer-only Configuration
    /// per supervisor block entry #5.
    internal static func _fetchURL(
        _ uri: URI,
        memo: inout [URI: Swift.String]
    ) throws(Lint.Run.Error) -> Swift.String {
        if let cached = memo[uri] {
            return cached
        }
        let content: Swift.String
        if uri.scheme?.value == "file" {
            content = try _readLocalFileForURL(uri)
        } else {
            content = try _fetchHTTPURL(uri)
        }
        memo[uri] = content
        return content
    }

    /// Read a `file://`-scheme `URI` by routing through the URI's
    /// typed `path` accessor (no manual scheme manipulation per
    /// principal type-discipline review).
    internal static func _readLocalFileForURL(
        _ uri: URI
    ) throws(Lint.Run.Error) -> Swift.String {
        guard let uriPath = uri.path else {
            throw .parentFetchFailed(url: uri, exitCode: -1, stderr: "URI has no path component")
        }
        // Reconstruct the filesystem path from URI.Path's typed
        // segments + isAbsolute. URI.Path drops the percent-encoding
        // surface; segments are decoded already. Joining with "/"
        // and prepending "/" if absolute yields the conventional
        // POSIX path string.
        let pathString: Swift.String
        if uriPath.isAbsolute {
            pathString = "/" + uriPath.segments.joined(separator: "/")
        } else {
            pathString = uriPath.segments.joined(separator: "/")
        }
        do {
            let filePath = try File.Path(pathString)
            let bytes: [UInt8] = try File(filePath).read.full { (span: Span<UInt8>) -> [UInt8] in
                var array: [UInt8] = []
                array.reserveCapacity(span.count)
                for i in 0..<span.count { array.append(span[i]) }
                return array
            }
            return Swift.String(decoding: bytes, as: UTF8.self)
        } catch {
            throw .parentFetchFailed(url: uri, exitCode: -1, stderr: "\(error)")
        }
    }

    /// Fetch an `http://` or `https://` `URI` by spawning
    /// `curl -fsSL <uri.value> -o <temp>`, reading the temp file,
    /// then deleting it.
    internal static func _fetchHTTPURL(
        _ uri: URI
    ) throws(Lint.Run.Error) -> Swift.String {
        let tempPath = _tempPathFor(url: uri)

        let configuration = Process.Spawn.Configuration(
            executable: "/usr/bin/curl",
            arguments: ["-fsSL", uri.value, "-o", tempPath]
        )

        let status: Process.Status
        do {
            status = try Process.Spawn.run(configuration)
        } catch {
            throw .parentFetchFailed(url: uri, exitCode: -1, stderr: "spawn: \(error)")
        }

        guard case .exited(let code) = status, code == 0 else {
            let exitCode: Int32
            switch status {
            case .exited(let c): exitCode = c
            case .signaled(let s): exitCode = -s
            case .stopped(let s): exitCode = -s
            }
            throw .parentFetchFailed(
                url: uri,
                exitCode: exitCode,
                stderr: ""  // captured-stderr support deferred — see Lint.Run.Error doc
            )
        }

        let content: Swift.String
        do {
            let filePath = try File.Path(tempPath)
            let bytes: [UInt8] = try File(filePath).read.full { (span: Span<UInt8>) -> [UInt8] in
                var array: [UInt8] = []
                array.reserveCapacity(span.count)
                for i in 0..<span.count { array.append(span[i]) }
                return array
            }
            content = Swift.String(decoding: bytes, as: UTF8.self)
        } catch {
            throw .parentFetchFailed(url: uri, exitCode: 0, stderr: "read temp: \(error)")
        }

        // Best-effort cleanup; ignore errors (temp file is deterministically
        // overwritten on next fetch of the same URI anyway).
        _ = try? Process.Spawn.run(
            Process.Spawn.Configuration(
                executable: "/bin/rm",
                arguments: ["-f", tempPath]
            )
        )

        return content
    }

    /// Deterministic temp-file path for a given `URI`. Sanitizes the
    /// URI's full string value via ``_sanitizeForPath(_:)`` so
    /// distinct URIs never collide on the same temp path; identical
    /// URIs (within or across processes) share a path, which is
    /// harmless because the content is the same.
    internal static func _tempPathFor(url uri: URI) -> Swift.String {
        "/tmp/swift-linter-fetch-\(_sanitizeForPath(uri.value)).tmp"
    }

    /// Filename-safe form of an arbitrary string (alphanumerics +
    /// `_-.` retained, everything else mapped to `_`). Deterministic;
    /// same input → same output within and across processes.
    internal static func _sanitizeForPath(_ string: Swift.String) -> Swift.String {
        var sanitized = ""
        for character in string {
            if character.isLetter || character.isNumber
                || character == "_" || character == "-" || character == "."
            {
                sanitized.append(character)
            } else {
                sanitized.append("_")
            }
        }
        return sanitized
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
    /// `parent` is the next-outer Configuration in the inheritance
    /// chain (or `nil` for the root tier). The returned Configuration
    /// inherits via `Lint.Configuration(inheriting: parent)`; layered
    /// override semantics are computed by ``Lint/Configuration/effectiveRules()``.
    ///
    /// Each ID in `disabledRuleIDs` becomes a
    /// `Lint.Rule.Configuration.disable(...)` entry at this layer,
    /// overriding any parent enable for the same rule TYPE per
    /// `effectiveRules()`'s "later layer wins" rule.
    internal static func _configuration(
        from manifest: Lint.Manifest,
        parent: Lint.Configuration?
    ) -> Lint.Configuration {
        let enabled = Set(manifest.enabledRuleIDs)
        let disabled = Set(manifest.disabledRuleIDs)
        return Lint.Configuration(
            inheriting: parent,
            rules: {
                for rule in Lint.Rule.builtIn {
                    let ruleID = type(of: rule).id
                    if disabled.contains(ruleID) {
                        Lint.Rule.Configuration.disable(type(of: rule))
                    } else if enabled.contains(ruleID) {
                        Lint.Rule.Configuration.enable(type(of: rule))
                    }
                }
            },
            excluded: manifest.excludedPaths
        )
    }

    /// Walk the parent chain starting from `rootURL`, fetching each
    /// parent's content and evaluating it via `Manifest.load`.
    ///
    /// Returns the chain in PARENT-FIRST order (root-most → tier
    /// closest to consumer). The consumer's own `Lint.Manifest` is
    /// not part of this chain — the resolver layers it on top.
    ///
    /// Cycle detection: visited URIs accumulate in a `Set<URI>` plus
    /// an order-preserving `[URI]` for diagnostics; revisit produces
    /// ``Lint/Run/Error/parentChainCycle(visited:at:)``. Depth
    /// backstop at 16 produces ``Lint/Run/Error/parentChainTooDeep(depth:)``.
    internal static func _resolveParentChain(
        rootURL: URI
    ) throws(Lint.Run.Error) -> [Lint.Manifest] {
        var visited: Set<URI> = []
        var visitedOrder: [URI] = []  // preserves chain order for diagnostics
        var memo: [URI: Swift.String] = [:]
        // Build child-to-root, reverse to parent-first at the end.
        var chain: [Lint.Manifest] = []
        var currentURI: URI? = rootURL
        var depth = 0

        while let uri = currentURI {
            if visited.contains(uri) {
                throw .parentChainCycle(visited: visitedOrder, at: uri)
            }
            visited.insert(uri)
            visitedOrder.append(uri)
            depth += 1
            if depth > 16 {
                throw .parentChainTooDeep(depth: depth)
            }
            let content = try _fetchURL(uri, memo: &memo)
            let manifest = try _evalParentManifest(content: content, url: uri)
            chain.append(manifest)
            currentURI = _parseParentURLFromContent(content)
        }

        chain.reverse()
        return chain
    }

    /// Evaluate a fetched parent's `Lint.swift` content as a typed
    /// `Lint.Manifest` value via `Manifest.load`.
    ///
    /// Materializes the content under
    /// `/tmp/swift-linter-parent-eval-<sanitized-uri>/Lint.swift`,
    /// then invokes `Manifest.load` against that as a fresh package
    /// root. Each parent eval is a swift-build subprocess; only the
    /// FETCH step is memoized (`Manifest.load` itself spawns a fresh
    /// process per call).
    internal static func _evalParentManifest(
        content: Swift.String,
        url uri: URI
    ) throws(Lint.Run.Error) -> Lint.Manifest {
        let tempDir = "/tmp/swift-linter-parent-eval-\(_sanitizeForPath(uri.value))"
        let tempLintFile = tempDir + "/Lint.swift"

        // Best-effort mkdir -p; failure surfaces as the subsequent write failure.
        _ = try? Process.Spawn.run(
            Process.Spawn.Configuration(
                executable: "/bin/mkdir",
                arguments: ["-p", tempDir]
            )
        )

        do {
            let filePath = try File.Path(tempLintFile)
            try File(filePath).write.atomic(content)
        } catch {
            throw .parentFetchFailed(
                url: uri,
                exitCode: 0,
                stderr: "write temp Lint.swift: \(error)"
            )
        }

        do {
            return try Manifest.load(
                Lint.Manifest.self,
                from: tempDir,
                named: "Lint.swift",
                valueName: "manifest",
                dependencies: _manifestDependencies()
            )
        } catch {
            throw .parentFetchFailed(
                url: uri,
                exitCode: 0,
                stderr: "manifest.load: \(error)"
            )
        }
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
