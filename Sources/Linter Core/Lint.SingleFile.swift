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
internal import JSON
internal import Manifest_Loader
internal import Manifest_Primitives
internal import Manifest_Resolver
internal import Process

/// Detection + dispatch for the unified single-file consumer manifest
/// shape (research recommendation Shape γ; see
/// `swift-institute/Research/2026-05-12-swift-linter-unified-consumer-manifest.md`).
///
/// A Shape-γ consumer places a `Lint.swift` at the package root with a
/// `// swift-linter-tools-version: 0.1` magic-comment header. The file
/// declares BOTH the SwiftPM dependencies the linter must fetch (rule
/// packs, SwiftSyntax) AND the rule activations to apply, in one
/// self-contained Swift literal:
///
/// ```swift
/// // swift-linter-tools-version: 0.1
/// import Linter
/// import Linter_Primitives_Rules
///
/// Lint.run(dependencies: [
///     .package(path: "../../swift-primitives-linter-rules",
///              products: ["Linter Primitives Rules"]),
/// ]) {
///     Lint.Rule.Bundle.primitives
/// }
/// ```
///
/// Detection (``detect(at:)``) confirms the file's presence at the
/// consumer root and the magic-comment header. Dispatch
/// (``dispatch(at:arguments:)``) parses the file via SwiftSyntax to
/// extract the `.package(...)` declarations, materializes a temporary
/// eval project at `<consumerRoot>/.swift-lint/eval/`, copies
/// `Lint.swift` as the eval target's `main.swift`, and spawns
/// `swift run --package-path <eval> Lint -- <args>`. The dispatched
/// executable IS the linter binary for the consumer — its stdout is
/// the authoritative diagnostic stream.
///
/// This dispatch path is intentionally additive. The existing
/// nested-package (`Lint/Package.swift`) and inert legacy single-file
/// (`let manifest: Lint.Manifest`) paths are unchanged; callers
/// detect in priority order: single-file Shape γ → nested-package →
/// legacy inert.
extension Lint {
    public enum SingleFile: Swift.Sendable {}
}

extension Lint.SingleFile {
    /// The magic-comment header that identifies a Shape-γ
    /// `Lint.swift`.
    ///
    /// Matched case-sensitively in the file's first leading-trivia
    /// block. Files without this header are NOT treated as Shape-γ —
    /// callers fall through to the next detection path.
    public static let toolsVersionMagicComment: Swift.String = "swift-linter-tools-version:"

    /// Canonicalize a CLI-supplied consumer-root path to its absolute
    /// form. When the path is `"."` or empty (the canonical
    /// `swift-linter .` invocation), substitutes the current working
    /// directory yielded by `currentWorkingDirectory()`; otherwise
    /// returns the path unchanged.
    ///
    /// SwiftPM rejects the literal `"."` as a package name in the
    /// materialized eval project (`unknown package '.'`), so the CLI
    /// must resolve `"."` to an absolute path before calling
    /// ``dispatch(at:arguments:)``. The cwd-yielding closure is
    /// injected so this helper stays platform-neutral and unit-testable
    /// without pulling kernel-tier dependencies into Linter Core; the
    /// CLI binds it to `Kernel.Directory.Working.current()` per the
    /// platform skill's L3-unifier composition discipline.
    @inlinable
    public static func canonicalize(
        consumerRoot: Swift.String,
        currentWorkingDirectory: () -> Swift.String?
    ) -> Swift.String {
        if consumerRoot.isEmpty || consumerRoot == "." {
            return currentWorkingDirectory() ?? consumerRoot
        }
        return consumerRoot
    }

    /// Detect whether `<consumerPackageRoot>/Lint.swift` exists AND
    /// carries the Shape-γ magic-comment header.
    ///
    /// Returns the path to the file when detection succeeds, `nil`
    /// otherwise. The magic-comment check is line-by-line over the
    /// file's first 30 lines (sufficient for the institute's
    /// canonical scaffolds; SE-0152 SwiftPM places the analogous
    /// `swift-tools-version:` directive at line 1).
    public static func detect(
        at consumerPackageRoot: Swift.String
    ) -> Swift.String? {
        // F-A1.9 (audit `2026-05-12-typed-primitive-adoption-audit.md`):
        // typed `File.Path` arithmetic replaces the prior
        // `consumerPackageRoot + "/Lint.swift"` concat. The boundary
        // remains `Swift.String` until Phase 2 types
        // `consumerPackageRoot` itself; an invalid root falls
        // through `nil` rather than throwing because `detect` is
        // explicitly silent-fallback.
        guard let consumerRoot: File.Path = try? File.Path(consumerPackageRoot) else {
            return nil
        }
        let candidate: Swift.String = (consumerRoot / "Lint.swift").string
        guard let directory = try? File.Directory(validating: consumerPackageRoot) else {
            return nil
        }
        guard let entries = try? directory.entries() else {
            return nil
        }
        var found = false
        for entry in entries where Swift.String(entry.name) == "Lint.swift" {
            found = true
            break
        }
        guard found else { return nil }
        guard let source = try? Self.readFile(at: candidate) else {
            return nil
        }
        return Self.hasMagicComment(in: source) ? candidate : nil
    }

    /// Scan the leading 30 lines of `source` for the
    /// ``toolsVersionMagicComment`` substring.
    @inlinable
    internal static func hasMagicComment(in source: Swift.String) -> Swift.Bool {
        var lineCount = 0
        for line in source.split(separator: "\n", maxSplits: 30, omittingEmptySubsequences: false) {
            if line.contains(Self.toolsVersionMagicComment) {
                return true
            }
            lineCount += 1
            if lineCount >= 30 { break }
        }
        return false
    }

    /// Read a file's full contents into a `Swift.String`.
    @usableFromInline
    internal static func readFile(at absolutePath: Swift.String) throws -> Swift.String {
        let path: File.Path = try File.Path(absolutePath)
        let bytes: [UInt8] = try File(path).read.full { (span: Span<UInt8>) -> [UInt8] in
            var array: [UInt8] = []
            array.reserveCapacity(span.count)
            for i in 0..<span.count {
                array.append(span[i])
            }
            return array
        }
        return Swift.String(decoding: bytes, as: UTF8.self)
    }

    /// Full dispatch path for a Shape-γ consumer:
    /// extract deps → resolve parent chain → materialize eval project
    /// → spawn `swift run`.
    ///
    /// Parent-chain resolution: the consumer's `Lint.swift` MAY carry
    /// one or more `// parent: <URL>` directives. Each parent is
    /// fetched via `Manifest.Resolver.walkParents`, evaluated via the
    /// subprocess manifest loader as a wire-format
    /// ``Lint/Manifest``, and folded parent-first into a single
    /// effective Manifest. The folded Manifest is JSON-serialized to
    /// a temp file; the file path is passed to the dispatched
    /// executable via the `SWIFT_LINTER_PARENT_MANIFEST` environment
    /// variable. The executable's
    /// ``Lint/run(dependencies:rules:)`` reads the env var, lifts
    /// the parent Manifest against the local rule registry, and
    /// threads the result as `inheriting:`.
    ///
    /// Returns the spawned `swift run` invocation's exit code as an
    /// `Int32`. A terminating signal `s` is encoded as `-s` so
    /// callers can distinguish abnormal termination from a regular
    /// non-zero exit.
    ///
    /// `arguments` is forwarded to the dispatched `Lint` executable
    /// (the consumer's `Lint.swift` as compiled in the eval project).
    public static func dispatch(
        at consumerPackageRoot: Swift.String,
        arguments: [Swift.String]
    ) throws(Lint.SingleFile.Error) -> Swift.Int32 {
        // F-A1.10 (audit `2026-05-12-typed-primitive-adoption-audit.md`):
        // typed `File.Path` arithmetic replaces the prior
        // `consumerPackageRoot + "/Lint.swift"` concat. The
        // surrounding boundary remains `Swift.String` until Phase 2.
        let consumerRoot: File.Path
        do throws(Paths.Path.Error) {
            consumerRoot = try File.Path(consumerPackageRoot)
        } catch {
            throw .materializationFailed(reason: "invalid consumerPackageRoot `\(consumerPackageRoot)`: \(error)")
        }
        let consumerLintSwiftPath: Swift.String = (consumerRoot / "Lint.swift").string
        let source: Swift.String
        do {
            source = try Self.readFile(at: consumerLintSwiftPath)
        } catch {
            throw .readFailed(path: consumerLintSwiftPath, description: "\(error)")
        }
        guard Self.hasMagicComment(in: source) else {
            throw .missingToolsVersion(path: consumerLintSwiftPath)
        }
        let dependencies: [Lint.SingleFile.PackageDependency] = try Lint.SingleFile.Extractor.extractDependencies(
            from: source,
            sourcePath: consumerLintSwiftPath,
            consumerPackageRoot: consumerPackageRoot
        )
        let evalRoot: Swift.String = try Lint.SingleFile.Materializer.materialize(
            consumerPackageRoot: consumerPackageRoot,
            consumerLintSwiftPath: consumerLintSwiftPath,
            dependencies: dependencies
        )

        // Parent-chain resolution. The folded parent Manifest is
        // serialized to a temp file and passed to the dispatched
        // executable via env var.
        let parentManifestPath: Swift.String? = try Self.resolveParentChain(
            consumerSource: source,
            consumerPackageRoot: consumerPackageRoot
        )

        let invocation: [Swift.String] =
            ["swift", "run", "--package-path", evalRoot, "Lint"] + arguments
        let environment: [Swift.String: Swift.String]?
        if let path: Swift.String = parentManifestPath {
            var snapshot: Environment.Snapshot = Environment.Snapshot.current()
            snapshot.values["SWIFT_LINTER_PARENT_MANIFEST"] = path
            environment = snapshot.values
        } else {
            environment = nil
        }
        let spawnConfiguration = Process.Spawn.Configuration(
            executable: "/usr/bin/env",
            arguments: invocation,
            environment: environment
        )
        let status: Process.Status
        do throws(Process.Error) {
            status = try Process.Spawn.run(spawnConfiguration)
        } catch {
            throw .spawnFailed(
                consumerPackageRoot: consumerPackageRoot,
                description: "\(error)"
            )
        }
        switch status {
        case .exited(let code): return code
        case .signaled(let s): return -s
        case .stopped(let s): return -s
        }
    }

    /// Walk the parent chain expressed in `consumerSource` and write
    /// the folded `Lint.Manifest` to a temp JSON file. Returns the
    /// path to the file when a chain is present, `nil` when no
    /// parent directive is found.
    ///
    /// Parent eval uses the same dependency set as
    /// ``Lint/Driver/resolveConfiguration(consumerPackageRoot:lintSwiftPathOverride:onMissingLinterPath:)``
    /// — JSON, File_System, Linter — resolved against
    /// `SWIFT_LINTER_PATH`. When the env var is unset the resolver
    /// cannot evaluate parents; the method returns `nil` and lint
    /// proceeds without parent inheritance.
    internal static func resolveParentChain(
        consumerSource: Swift.String,
        consumerPackageRoot: Swift.String
    ) throws(Lint.SingleFile.Error) -> Swift.String? {
        guard let linterPath: Swift.String = Environment.read("SWIFT_LINTER_PATH") else {
            return nil
        }
        // F-A1.11 (audit `2026-05-12-typed-primitive-adoption-audit.md`):
        // `Paths.Path.parent` replaces the prior `linterPath + "/.."`
        // dot-segment suffix; the typed primitive owns dot-segment
        // semantics. The workspace is the parent directory of the
        // swift-linter package — the env var points at the package
        // root by contract. Parse / parent failure folds into the
        // method's documented silent-fallback contract (return `nil`
        // → no parent inheritance).
        guard let linter: File.Path = try? File.Path(linterPath),
              let workspace: File.Path = linter.parent
        else {
            return nil
        }
        let parentDependencies: [Manifest.Dependency] = [
            Manifest.Dependency(
                path: (workspace / "swift-json").string,
                name: "swift-json",
                product: "JSON",
                imports: ["JSON"]
            ),
            Manifest.Dependency(
                path: (workspace / "swift-file-system").string,
                name: "swift-file-system",
                product: "File System",
                imports: ["File_System"]
            ),
            Manifest.Dependency(
                path: linterPath,
                name: "swift-linter",
                product: "Linter",
                imports: ["Linter"]
            )
        ]
        let parentChain: [Lint.Manifest]
        do {
            parentChain = try Manifest.Resolver<Lint.Manifest, Lint.Manifest>.walkParents(
                from: consumerSource,
                filename: "Lint.swift",
                dependencies: parentDependencies
            )
        } catch {
            // Parent chain failure — silent fall-through to no
            // inheritance. The dispatch can still proceed; the
            // consumer's own activations are unaffected.
            return nil
        }
        guard !parentChain.isEmpty else {
            return nil
        }
        let folded: Lint.Manifest = Self.foldParents(parentChain)
        let serialized: JSON = Lint.Manifest.serialize(folded)
        let jsonString: Swift.String = serialized.jsonString()
        // F-A1.12 (audit `2026-05-12-typed-primitive-adoption-audit.md`):
        // typed `File.Path` arithmetic replaces the prior
        // `consumerPackageRoot + "/.swift-lint/parent-manifest.json"`
        // concat. Component-literal `/` operator means the segment
        // shapes are compile-time validated.
        let filePath: File.Path
        do throws(Paths.Path.Error) {
            let consumerRoot = try File.Path(consumerPackageRoot)
            filePath = consumerRoot / ".swift-lint" / "parent-manifest.json"
        } catch {
            throw .materializationFailed(reason: "invalid consumerPackageRoot `\(consumerPackageRoot)`: \(error)")
        }
        let tempPath: Swift.String = filePath.string
        do {
            try File(filePath).write.atomic(jsonString)
        } catch {
            throw .materializationFailed(reason: "write parent manifest \(tempPath): \(error)")
        }
        return tempPath
    }

    /// Fold a parent-first chain of `Lint.Manifest` values into a
    /// single effective Manifest. Order is preserved (root-most first,
    /// closest-to-consumer last); the consumer's
    /// ``Lint/Configuration/effectiveRules()`` handles dedup and
    /// override semantics (later wins per rule ID).
    internal static func foldParents(_ chain: [Lint.Manifest]) -> Lint.Manifest {
        var enabled: [Lint.Rule.ID] = []
        var disabled: [Lint.Rule.ID] = []
        var excluded: [File.Path] = []
        for parent in chain {
            enabled.append(contentsOf: parent.enabledRuleIDs)
            disabled.append(contentsOf: parent.disabledRuleIDs)
            excluded.append(contentsOf: parent.excludedPaths)
        }
        return Lint.Manifest(
            enabledRuleIDs: enabled,
            disabledRuleIDs: disabled,
            excludedPaths: excluded
        )
    }

    /// Dispatched-executable side of the parent-chain mechanism:
    /// read the parent `Lint.Manifest` from the JSON file at the
    /// path in the `SWIFT_LINTER_PARENT_MANIFEST` environment
    /// variable, and lift it against the supplied local rule
    /// `registry`.
    ///
    /// Returns the resulting `Lint.Configuration` when the env var
    /// is set AND the file reads + parses successfully. Returns
    /// `nil` when:
    /// - The env var is unset (no parent chain was resolved by the
    ///   coordinator, or the dispatched executable is being run
    ///   directly without coordinator setup).
    /// - The file is missing or unreadable.
    /// - The file's contents fail to deserialize as a
    ///   ``Lint/Manifest``.
    ///
    /// Failures are silent on the dispatched-executable side —
    /// they fall through to consumer-only configuration (no parent
    /// inheritance). The coordinator side surfaces parent-chain
    /// failures explicitly via the dispatch result.
    public static func parentConfiguration(
        registry: [Lint.Rule.ID: Lint.Rule]
    ) -> Lint.Configuration? {
        guard let path: Swift.String = Environment.read("SWIFT_LINTER_PARENT_MANIFEST") else {
            return nil
        }
        let source: Swift.String
        do {
            source = try Self.readFile(at: path)
        } catch {
            return nil
        }
        let parsed: JSON
        do {
            parsed = try JSON.parse(source)
        } catch {
            return nil
        }
        let manifest: Lint.Manifest
        do {
            manifest = try Lint.Manifest.deserialize(parsed)
        } catch {
            return nil
        }
        return Lint.Configuration.lift(manifest: manifest, registry: registry)
    }
}
