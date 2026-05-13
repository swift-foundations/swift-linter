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
internal import Package_Primitives
internal import SwiftParser
internal import SwiftSyntax

extension Lint.SingleFile {
    /// Syntactic extraction of `.package(...)` dependency declarations
    /// from a consumer's `Lint.swift` source.
    ///
    /// The extractor walks the parsed AST top-down, finds the first
    /// top-level `Lint.run(...)` (or unqualified `run(...)`) call
    /// expression containing a `dependencies:` labeled argument, and
    /// returns each `.package(...)` call as a structured
    /// ``Lint/SingleFile/PackageDependency`` value.
    ///
    /// Extraction is purely syntactic — no semantic analysis, no
    /// resolution. The call site IS the source of truth; mistakes
    /// (typos in `path:`, missing `products:`) surface as typed
    /// ``Lint/SingleFile/Error`` values rather than runtime traps.
    public enum Extractor {}
}

extension Lint.SingleFile.Extractor {
    /// Extract `.package(...)` dependency declarations from the
    /// `dependencies:` argument of the consumer's `Lint.run(...)`
    /// call.
    ///
    /// `consumerPackageRoot` is the directory path of the consumer's
    /// own package — needed to derive a SwiftPM-resolvable package
    /// name for `.package(path: ".")` / `.package(path: "")`
    /// self-references (the literal `"."` is not a valid SwiftPM
    /// package name; the consumer-root's directory basename is).
    /// F-A2.7 (audit `Research/2026-05-12-typed-primitive-adoption-audit.md`):
    /// the audit marks the extractor's path parameters as
    /// Ambiguous (boundary judgement). The boundary in this Phase 2
    /// pass moves toward `File.Path` to keep the artery typed
    /// end-to-end; AST-extracted string literals (which genuinely
    /// originate as `Swift.String` from SwiftSyntax) remain
    /// `Swift.String` and are not retyped here.
    public static func dependencies(
        from source: Swift.String,
        sourcePath: File.Path,
        consumerPackageRoot: File.Path
    ) throws(Lint.SingleFile.Error) -> [Lint.SingleFile.PackageDependency] {
        let sourceFile: SourceFileSyntax = Parser.parse(source: source)
        guard let runCall: FunctionCallExprSyntax = findRunCall(in: sourceFile) else {
            throw .dependenciesNotFound(
                path: sourcePath,
                description: "no top-level Lint.run(...) call expression found in source"
            )
        }
        guard let dependenciesArg: LabeledExprSyntax = runCall.arguments.first(
            where: { $0.label?.text == "dependencies" }
        ) else {
            throw .dependenciesNotFound(
                path: sourcePath,
                description: "Lint.run(...) call has no `dependencies:` argument"
            )
        }
        guard let arrayExpr: ArrayExprSyntax = dependenciesArg.expression.as(ArrayExprSyntax.self) else {
            throw .dependenciesNotFound(
                path: sourcePath,
                description: "Lint.run(...) `dependencies:` argument is not a literal array; got `\(dependenciesArg.expression.description)`"
            )
        }
        var deps: [Lint.SingleFile.PackageDependency] = []
        for element in arrayExpr.elements {
            guard let call: FunctionCallExprSyntax = element.expression.as(FunctionCallExprSyntax.self) else {
                throw .malformedPackageCall(
                    path: sourcePath,
                    description: "dependencies[] element is not a function call: `\(element.expression.description)`"
                )
            }
            let dep: Lint.SingleFile.PackageDependency = try parsePackageCall(
                call,
                sourcePath: sourcePath,
                consumerPackageRoot: consumerPackageRoot
            )
            deps.append(dep)
        }
        return deps
    }

    /// Find the first top-level expression that is a `Lint.run(...)`
    /// or unqualified `run(...)` function call.

    internal static func findRunCall(in sourceFile: SourceFileSyntax) -> FunctionCallExprSyntax? {
        for item in sourceFile.statements {
            guard let expr: ExprSyntax = item.item.as(ExprSyntax.self) else { continue }
            guard let call: FunctionCallExprSyntax = expr.as(FunctionCallExprSyntax.self) else { continue }
            if Self.isLintRunCall(call) {
                return call
            }
        }
        return nil
    }

    /// Match `Lint.run(...)` (qualified) or `run(...)` (unqualified).

    internal static func isLintRunCall(_ call: FunctionCallExprSyntax) -> Swift.Bool {
        if let member: MemberAccessExprSyntax = call.calledExpression.as(MemberAccessExprSyntax.self) {
            guard member.declName.baseName.text == "run" else { return false }
            guard let base: DeclReferenceExprSyntax = member.base?.as(DeclReferenceExprSyntax.self) else {
                return true
            }
            return base.baseName.text == "Lint"
        }
        if let ref: DeclReferenceExprSyntax = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text == "run"
        }
        return false
    }

    /// Parse a `.package(path:products:)` or
    /// `.package(url:from:products:)` or
    /// `.package(url:_:_:products:)` call into a
    /// ``Lint/SingleFile/PackageDependency``.

    internal static func parsePackageCall(
        _ call: FunctionCallExprSyntax,
        sourcePath: File.Path,
        consumerPackageRoot: File.Path
    ) throws(Lint.SingleFile.Error) -> Lint.SingleFile.PackageDependency {
        guard let member: MemberAccessExprSyntax = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "package"
        else {
            throw .malformedPackageCall(
                path: sourcePath,
                description: "expected `.package(...)` call; got `\(call.calledExpression.description)`"
            )
        }

        var pathArg: Swift.String?
        var urlArg: Swift.String?
        var fromArg: Swift.String?
        var rangeBounds: [Swift.String] = []
        var productsArg: [Swift.String]?

        for arg in call.arguments {
            switch arg.label?.text {
            case "path":
                pathArg = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)
            case "url":
                urlArg = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)
            case "from":
                fromArg = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)
            case "products":
                productsArg = try Self.extractStringArray(arg.expression, sourcePath: sourcePath)
            case nil:
                // Unlabeled positional arg — accepted for the
                // `.package(url:_:_:products:)` range form's lower
                // and upper bounds.
                let value: Swift.String = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)
                rangeBounds.append(value)
            default:
                throw .malformedPackageCall(
                    path: sourcePath,
                    description: "unexpected `\(arg.label?.text ?? "")` argument on `.package(...)`"
                )
            }
        }

        guard let productsRaw: [Swift.String] = productsArg, !productsRaw.isEmpty else {
            throw .malformedPackageCall(
                path: sourcePath,
                description: "`.package(...)` requires a non-empty `products:` argument"
            )
        }

        let source: Lint.SingleFile.PackageDependency.Source
        let derivedName: Swift.String
        if let path: Swift.String = pathArg {
            source = .path(path)
            derivedName = Self.packageName(fromPath: path, consumerPackageRoot: consumerPackageRoot)
        } else if let url: Swift.String = urlArg {
            if let from: Swift.String = fromArg {
                source = .urlFrom(url: url, from: from)
            } else if rangeBounds.count == 2 {
                source = .urlRange(url: url, lower: rangeBounds[0], upper: rangeBounds[1])
            } else {
                throw .malformedPackageCall(
                    path: sourcePath,
                    description: "`.package(url:...)` requires either `from:` or two positional version-range arguments; got `\(call.description)`"
                )
            }
            derivedName = Self.packageName(fromURL: url)
        } else {
            throw .malformedPackageCall(
                path: sourcePath,
                description: "`.package(...)` requires either `path:` or `url:` argument"
            )
        }

        let products: [Product.Name] = productsRaw.map { Product.Name($0) }
        return Lint.SingleFile.PackageDependency(
            source: source,
            name: Package.Name(derivedName),
            products: products
        )
    }

    /// Extract the literal string value from a
    /// `StringLiteralExprSyntax`.

    internal static func extractStringLiteral(
        _ expr: ExprSyntax,
        sourcePath: File.Path
    ) throws(Lint.SingleFile.Error) -> Swift.String {
        guard let literal: StringLiteralExprSyntax = expr.as(StringLiteralExprSyntax.self) else {
            throw .malformedPackageCall(
                path: sourcePath,
                description: "expected string literal; got `\(expr.description)`"
            )
        }
        guard literal.segments.count == 1,
              let segment: StringSegmentSyntax = literal.segments.first?.as(StringSegmentSyntax.self)
        else {
            throw .malformedPackageCall(
                path: sourcePath,
                description: "string literal must be a single segment with no interpolation; got `\(literal.description)`"
            )
        }
        return segment.content.text
    }

    /// Extract a `[String]` value from an `ArrayExprSyntax` whose
    /// elements are string literals.

    internal static func extractStringArray(
        _ expr: ExprSyntax,
        sourcePath: File.Path
    ) throws(Lint.SingleFile.Error) -> [Swift.String] {
        guard let arrayExpr: ArrayExprSyntax = expr.as(ArrayExprSyntax.self) else {
            throw .malformedPackageCall(
                path: sourcePath,
                description: "expected array literal; got `\(expr.description)`"
            )
        }
        var result: [Swift.String] = []
        for element in arrayExpr.elements {
            let value: Swift.String = try Self.extractStringLiteral(element.expression, sourcePath: sourcePath)
            result.append(value)
        }
        return result
    }

    /// Derive a SwiftPM package name from a `path:` argument's value.
    ///
    /// Self-reference shortcuts: `"."` and the empty string both name
    /// the consumer's own package. SwiftPM rejects the literal `"."`
    /// as a package name (`unknown package '.'`); for these forms the
    /// derived name is the consumer-root directory's basename instead
    /// — SwiftPM resolves `path:`-form packages by directory, and the
    /// directory basename typically matches the Package.swift `name:`
    /// field (e.g., `swift-cardinal-primitives`).
    ///
    /// The companion path-resolution shortcut lives at
    /// ``Lint/SingleFile/Materializer/resolveConsumerPath(_:relativeRoot:)``.
    /// `consumerPackageRoot` is canonicalized at the CLI boundary via
    /// ``Lint/SingleFile/canonicalize(consumerRoot:currentWorkingDirectory:)``
    /// before reaching this site, so basename derivation receives an
    /// absolute path even when the CLI is invoked as `swift-linter .`.

    internal static func packageName(
        fromPath path: Swift.String,
        consumerPackageRoot: File.Path
    ) -> Swift.String {
        // `path` is the AST-extracted SwiftPM literal (genuinely
        // string-shaped — it's source text being copied into the
        // generated PackageDescription); only `consumerPackageRoot`
        // is typed per the Phase 2 boundary.
        if path.isEmpty || path == "." {
            return consumerPackageRoot.components.last?.string ?? consumerPackageRoot.string
        }
        return basename(of: path)
    }

    /// Slash-trimmed basename of a path-shaped string.
    ///
    /// Returns the last component of the typed-Path form of `path`.
    /// Used by both `packageName(fromPath:)` and
    /// `packageName(fromPath:consumerPackageRoot:)` for the
    /// non-self-reference case; the typed primitive owns trailing-
    /// slash trimming and component segmentation, so this helper is
    /// a thin adapter at the bare-string boundary.
    ///
    /// F-A1.4 in `swift-linter/Research/2026-05-12-typed-primitive-adoption-audit.md`.
    private static func basename(of path: Swift.String) -> Swift.String {
        let typed: File.Path
        do throws(Paths.Path.Error) {
            typed = try File.Path(path)
        } catch {
            return path
        }
        return typed.components.last?.string ?? path
    }

    /// Derive a SwiftPM package name from a `url:` argument's value.

    internal static func packageName(fromURL url: Swift.String) -> Swift.String {
        var trimmed: Swift.String = url
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix(".git") {
            trimmed.removeLast(4)
        }
        if let lastSlash: Swift.String.Index = trimmed.lastIndex(of: "/") {
            return Swift.String(trimmed[trimmed.index(after: lastSlash)...])
        }
        return trimmed
    }

}
