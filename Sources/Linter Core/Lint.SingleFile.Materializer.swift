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
public import File_System
internal import Version_Primitives
internal import Version_Primitives_Standard_Library_Integration

extension Lint.SingleFile {
    /// Renders the eval project (`Package.swift` + `Sources/Lint/main.swift`)
    /// for a Shape-γ consumer.
    ///
    /// Materializes at `<consumerRoot>/.swift-lint/eval/` —
    /// gitignored cache directory analogous to SwiftPM's `.build/`.
    /// Always overwrites; the eval project is fully derived from the
    /// consumer's `Lint.swift` plus the extracted dependencies, so
    /// re-rendering is idempotent.
    public enum Materializer {}
}

extension Lint.SingleFile.Materializer {
    /// Materialize the eval project on disk and return the
    /// eval-root directory path.
    ///
    /// F-A2.4 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
    /// `consumerPackageRoot` and `consumerLintSwiftPath` are typed
    /// `File.Path`; the return value is also `File.Path`. The
    /// internal typed-Path chain from Phase 1 collapses to single
    /// operations once the entry-point types match.
    public static func materialize(
        consumerPackageRoot: File.Path,
        consumerLintSwiftPath: File.Path,
        dependencies: [Lint.SingleFile.PackageDependency]
    ) throws(Lint.SingleFile.Error) -> File.Path {
        // `/` operator's `(Path, Component)` overload — `Component`
        // is `ExpressibleByStringLiteral`, so the segment literals
        // typecheck without throwing component construction at call
        // sites (compile-time-known component shapes can never fail
        // path-component validation).
        let evalRoot: File.Path = consumerPackageRoot / ".swift-lint" / "eval"
        let sourcesDirectory: File.Path = evalRoot / "Sources" / "Lint"
        let packageSwiftPath: File.Path = evalRoot / "Package.swift"
        let mainSwiftPath: File.Path = sourcesDirectory / "main.swift"

        try Self.createDirectoryRecursive(at: sourcesDirectory)

        let linterPath: File.Path
        if let raw: Swift.String = Environment.read("SWIFT_LINTER_PATH") {
            do throws(Paths.Path.Error) {
                linterPath = try File.Path(raw)
            } catch {
                throw .materializationFailed(
                    reason: "SWIFT_LINTER_PATH value is not a valid path: \(error)"
                )
            }
        } else {
            throw .materializationFailed(
                reason: "SWIFT_LINTER_PATH environment variable not set; cannot resolve swift-linter dependency for the eval project."
            )
        }

        let packageSwift: Swift.String = try Self.renderPackageSwift(
            consumerPackageRoot: consumerPackageRoot,
            evalRoot: evalRoot,
            linterPath: linterPath,
            dependencies: dependencies
        )
        try Self.writeAtomic(packageSwift, to: packageSwiftPath)

        let consumerSource: Swift.String = try Self.readFile(at: consumerLintSwiftPath)
        try Self.writeAtomic(consumerSource, to: mainSwiftPath)

        return evalRoot
    }

    /// Render the eval project's `Package.swift` source.
    ///
    /// Emits:
    ///
    /// - One `.package(...)` dependency clause per
    ///   ``Lint/SingleFile/PackageDependency`` plus one for
    ///   `swift-linter` itself (resolved via `SWIFT_LINTER_PATH`).
    /// - One `.product(name:package:)` target-dependency line per
    ///   product per dependency.
    /// - One ecosystem `SwiftSetting` block matching the swift-linter
    ///   target settings (strict memory safety, upcoming features).
    fileprivate static func renderPackageSwift(
        consumerPackageRoot: File.Path,
        evalRoot: File.Path,
        linterPath: File.Path,
        dependencies: [Lint.SingleFile.PackageDependency]
    ) throws(Lint.SingleFile.Error) -> Swift.String {
        // Consumer-declared `.package(path: X)` paths are written by
        // the consumer relative to the consumer's package root. The
        // eval project's Package.swift sits at
        // `<consumerRoot>/.swift-lint/eval/Package.swift`, two
        // directory levels below the consumer root. Path-form deps
        // are rewritten to add `../../` prefix so they resolve from
        // the eval Package.swift's location.
        let evalRelativeToConsumer: Swift.String = "../.."

        // The eval project's SwiftPM tools version. Routed through
        // `Version.Tools` per Thread G phase G.2 (HANDOFF
        // `HANDOFF-thread-g-dependency-typed-primitive-adoption.md`) —
        // the literal flows through the typed primitive so a change
        // here surfaces as a typed-value edit, not a raw-string edit.
        let evalToolsVersion: Version.Tools = "6.3.1"

        var lines: [Swift.String] = [
            "// swift-tools-version: \(evalToolsVersion)",
            "// AUTO-GENERATED by swift-linter. DO NOT EDIT.",
            "// Source: \(consumerPackageRoot.string)/Lint.swift",
            "",
            "import PackageDescription",
            "",
            "let package = Package(",
            "    name: \"Lint\",",
            "    platforms: [",
            "        .macOS(.v26),",
            "    ],",
            "    products: [",
            "        .executable(name: \"Lint\", targets: [\"Lint\"]),",
            "    ],",
            "    dependencies: ["
        ]

        // swift-linter dep — always added.
        lines.append("        .package(path: \"\(linterPath.string)\"),")

        // Consumer-declared deps.
        for dep in dependencies {
            switch dep.source {
            case .path(let path):
                let resolvedPath: Swift.String = try Self.resolve(path, relativeTo: evalRelativeToConsumer)
                lines.append("        .package(path: \"\(resolvedPath)\"),")
            case .urlFrom(let url, let from):
                lines.append("        .package(url: \"\(url)\", from: \"\(from)\"),")
            case .urlRange(let url, let lower, let upper):
                lines.append("        .package(url: \"\(url)\", \"\(lower)\"..<\"\(upper)\"),")
            }
        }

        lines.append(contentsOf: [
            "    ],",
            "    targets: [",
            "        .executableTarget(",
            "            name: \"Lint\",",
            "            dependencies: ["
        ])

        // Linter product — always added.
        lines.append("                .product(name: \"Linter\", package: \"swift-linter\"),")

        // Consumer-declared products.
        for dep in dependencies {
            for product in dep.products {
                lines.append("                .product(name: \"\(product)\", package: \"\(dep.name)\"),")
            }
        }

        lines.append(contentsOf: [
            "            ]",
            "        ),",
            "    ],",
            "    swiftLanguageModes: [.v6]",
            ")",
            "",
            "for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {",
            "    let ecosystem: [SwiftSetting] = [",
            "        .enableUpcomingFeature(\"ExistentialAny\"),",
            "        .enableUpcomingFeature(\"InternalImportsByDefault\"),",
            "        .enableUpcomingFeature(\"MemberImportVisibility\"),",
            "        .enableUpcomingFeature(\"NonisolatedNonsendingByDefault\"),",
            "    ]",
            "    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem",
            "}",
            ""
        ])

        return lines.joined(separator: "\n")
    }

    /// Resolve a consumer's path-relative dep into a path relative
    /// to the eval project's `Package.swift`.
    ///
    /// Example: consumer writes `.package(path: "../../swift-primitives-linter-rules")`.
    /// The eval Package.swift lives at `<consumerRoot>/.swift-lint/eval/`,
    /// two levels deeper than the consumer root. To reach the same
    /// target, the eval prepends `../../` → `../../../../swift-primitives-linter-rules`.
    /// Joining goes through ``File/Path`` so separator semantics and
    /// component validation come from the typed primitive — not raw
    /// string concatenation.
    ///
    /// Self-reference shortcuts: `"."` and the empty string both name
    /// the consumer's own package root. Naive concatenation
    /// (`"../.." + "/" + "."`) produces `"../../."` which SwiftPM's
    /// `.package(path:)` parser rejects with "unknown package '.'".
    /// Both forms collapse to `relativeRoot` here so a consumer can
    /// declare `.package(path: ".", products: [...])` to refer to its
    /// own package. The shortcut runs ahead of `File.Path` construction
    /// — `File.Path("")` throws `.empty`, and `Path("./X").appending(...)`
    /// retains the leading `.` literal that SwiftPM rejects.
    @usableFromInline
    internal static func resolve(
        _ consumerPath: Swift.String,
        relativeTo root: Swift.String
    ) throws(Lint.SingleFile.Error) -> Swift.String {
        // Self-reference shortcuts — both name the consumer's own
        // package root, which is exactly `root` from the eval
        // project's vantage. Runs ahead of typed-path construction
        // because both `""` and `"."` either fail `Path` validation or
        // retain a `.` segment SwiftPM cannot resolve.
        if consumerPath.isEmpty || consumerPath == "." {
            return root
        }
        let consumer: File.Path
        let base: File.Path
        do throws(Paths.Path.Error) {
            consumer = try File.Path(consumerPath)
            base = try File.Path(root)
        } catch {
            throw .materializationFailed(
                reason: "invalid SwiftPM path-form dep `\(consumerPath)` (relative to `\(root)`): \(error)"
            )
        }
        // `Path.appending(_:)` returns `other` unchanged when absolute
        // — preserves the prior absolute-passthrough behaviour without
        // an explicit `hasPrefix("/")` branch.
        return base.appending(consumer).string
    }

    /// Create a directory tree recursively.
    fileprivate static func createDirectoryRecursive(
        at path: File.Path
    ) throws(Lint.SingleFile.Error) {
        do throws(File.System.Create.Directory.Error) {
            try File.Directory(path).create.recursive()
        } catch {
            throw .materializationFailed(reason: "create directory \(path.string): \(error)")
        }
    }

    /// Write a string to a file atomically.
    fileprivate static func writeAtomic(
        _ contents: Swift.String,
        to path: File.Path
    ) throws(Lint.SingleFile.Error) {
        do throws(File.System.Write.Atomic.Error) {
            try File(path).write.atomic(contents)
        } catch {
            throw .materializationFailed(reason: "write \(path.string): \(error)")
        }
    }

    /// Read a file's full contents into a `Swift.String`.
    fileprivate static func readFile(at path: File.Path) throws(Lint.SingleFile.Error) -> Swift.String {
        let bytes: [UInt8]
        do throws(File.System.Read.Full.Error) {
            bytes = try File(path).read.full { (span: Span<UInt8>) -> [UInt8] in
                var array: [UInt8] = []
                array.reserveCapacity(span.count)
                for i in 0..<span.count {
                    array.append(span[i])
                }
                return array
            }
        } catch {
            throw .readFailed(path: path, description: "\(error)")
        }
        return Swift.String(decoding: bytes, as: UTF8.self)
    }
}
