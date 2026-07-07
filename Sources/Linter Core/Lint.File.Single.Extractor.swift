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
public import Package_Primitives
public import SPM_Standard
internal import SwiftParser
internal import SwiftSyntax
internal import Version_Primitives

extension Lint.File.Single {
    /// Syntactic extraction of `.package(...)` dependency declarations
    /// from a consumer's `Lint.swift` source.
    ///
    /// The extractor walks the parsed AST top-down, finds the first
    /// top-level `Lint.run(...)` (or unqualified `run(...)`) call
    /// expression containing a `dependencies:` labeled argument, and
    /// returns each `.package(...)` call as a structured
    /// ``Lint/File/Single/PackageDependency`` value.
    ///
    /// Extraction is purely syntactic — no semantic analysis, no
    /// resolution. The call site IS the source of truth; mistakes
    /// (typos in `path:`, missing `products:`) surface as typed
    /// ``Lint/File/Single/Error`` values rather than runtime traps.
    public enum Extractor {}
}

extension Lint.File.Single.Extractor {
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
    ) throws(Lint.File.Single.Error) -> [Package.Dependency] {
        try Self.dependencies(
            parsed: Parser.parse(source: source),
            sourcePath: sourcePath,
            consumerPackageRoot: consumerPackageRoot
        )
    }

    /// Extract `.package(...)` declarations from a PRE-PARSED tree, so the
    /// dispatch pipeline can parse `Lint.swift` exactly ONCE and thread the
    /// same tree to both the ``Classifier`` and this extractor.
    ///
    /// The public
    /// ``dependencies(from:sourcePath:consumerPackageRoot:)`` is a thin wrapper
    /// that parses, for callers (and tests) that hold only the text.
    internal static func dependencies(
        parsed sourceFile: SourceFileSyntax,
        sourcePath: File.Path,
        consumerPackageRoot: File.Path
    ) throws(Lint.File.Single.Error) -> [Package.Dependency] {
        guard let runCall: FunctionCallExprSyntax = Lint.File.Single.Invocation.find(in: sourceFile) else {
            throw .dependenciesNotFound(
                path: sourcePath,
                description: "no top-level Lint.run(...) call expression found in source"
            )
        }
        guard
            let dependenciesArg: LabeledExprSyntax = runCall.arguments.first(
                where: { $0.label?.text == "dependencies" }
            )
        else {
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
        var deps: [Package.Dependency] = []
        for element in arrayExpr.elements {
            guard let call: FunctionCallExprSyntax = element.expression.as(FunctionCallExprSyntax.self) else {
                throw .malformedPackageCall(
                    path: sourcePath,
                    description: "dependencies[] element is not a function call: `\(element.expression.description)`"
                )
            }
            let dep: Package.Dependency = try parsePackageCall(
                call,
                sourcePath: sourcePath,
                consumerPackageRoot: consumerPackageRoot
            )
            deps.append(dep)
        }
        return deps
    }

    /// Parse a `.package(path:products:)` or
    /// `.package(url:from:products:)` or
    /// `.package(url:_:_:products:)` call into a
    /// ``Lint/File/Single/PackageDependency``.

    fileprivate static func parsePackageCall(
        _ call: FunctionCallExprSyntax,
        sourcePath: File.Path,
        consumerPackageRoot: File.Path
    ) throws(Lint.File.Single.Error) -> Package.Dependency {
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
        var branchArg: Swift.String?

        for arg in call.arguments {
            switch arg.label?.text {
            case "path":
                pathArg = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)

            case "url":
                urlArg = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)

            case "from":
                fromArg = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)

            case "branch":
                branchArg = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)

            case "products":
                productsArg = try Self.extractStringArray(arg.expression, sourcePath: sourcePath)

            case nil:
                // Unlabeled positional arg — accepted for the
                // `.package(url:_:products:)` range form.
                //
                // Thread G G.1 (HANDOFF
                // `HANDOFF-thread-g-dependency-typed-primitive-adoption.md`)
                // moved the call-site shape from two positional string
                // literals to a single `Swift.Range<Version.Semantic>`
                // literal (`"X"..<"Y"`). The Extractor recognises both:
                // a `..<` range expression yields both bounds in one
                // arg; a bare string literal yields one bound (legacy
                // two-positional form).
                if let (lower, upper) = try Self.extractRangeBounds(arg.expression, sourcePath: sourcePath) {
                    rangeBounds.append(lower)
                    rangeBounds.append(upper)
                } else {
                    let value: Swift.String = try Self.extractStringLiteral(arg.expression, sourcePath: sourcePath)
                    rangeBounds.append(value)
                }

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

        let source: Package.Dependency.Source
        let derivedName: Swift.String
        if let pathString: Swift.String = pathArg {
            let path: Paths.Path
            do throws(Paths.Path.Error) {
                path = try Paths.Path(pathString)
            } catch {
                throw .malformedPackageCall(
                    path: sourcePath,
                    description: "`.package(path:...)` carries an invalid path `\(pathString)`: \(error)"
                )
            }
            source = .path(path)
            derivedName = Self.name(at: pathString, consumerPackageRoot: consumerPackageRoot)
        } else if let urlString: Swift.String = urlArg {
            let url: URI
            do throws(URIError) {
                url = try URI(urlString)
            } catch {
                throw .malformedPackageCall(
                    path: sourcePath,
                    description: "`.package(url:...)` carries an invalid URI `\(urlString)`: \(error)"
                )
            }
            if let from: Swift.String = fromArg {
                let version: Version.Semantic = try Self.parseSemantic(
                    from,
                    sourcePath: sourcePath,
                    role: "from"
                )
                source = .url(url, from: version)
            } else if rangeBounds.count == 2 {
                let lower: Version.Semantic = try Self.parseSemantic(
                    rangeBounds[0],
                    sourcePath: sourcePath,
                    role: "range lower bound"
                )
                let upper: Version.Semantic = try Self.parseSemantic(
                    rangeBounds[1],
                    sourcePath: sourcePath,
                    role: "range upper bound"
                )
                source = .url(url, lower..<upper)
            } else if let branch: Swift.String = branchArg {
                source = .url(url, branch: branch)
            } else {
                throw .malformedPackageCall(
                    path: sourcePath,
                    description: "`.package(url:...)` requires `from:`, `branch:`, or two positional version-range arguments; got `\(call.description)`"
                )
            }
            derivedName = Self.name(at: urlString)
        } else {
            throw .malformedPackageCall(
                path: sourcePath,
                description: "`.package(...)` requires either `path:` or `url:` argument"
            )
        }

        let products: [Product.Name] = productsRaw.map { Product.Name($0) }
        return Package.Dependency(
            source: source,
            name: Package.Name(derivedName),
            products: products
        )
    }

    /// Extract the literal string value from a
    /// `StringLiteralExprSyntax`.

    fileprivate static func extractStringLiteral(
        _ expr: ExprSyntax,
        sourcePath: File.Path
    ) throws(Lint.File.Single.Error) -> Swift.String {
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

    /// Extract the `(lower, upper)` string-literal bounds from a
    /// `"X"..<"Y"` range expression.
    ///
    /// Returns `nil` when the
    /// expression is not a half-open range with string-literal
    /// operands, so the caller can fall back to single-literal
    /// extraction.
    ///
    /// SwiftPM's `Range<Version>` form is parsed by SwiftSyntax as
    /// a `SequenceExprSyntax` with three elements: lower-literal,
    /// the `..<` binary operator, upper-literal. The Extractor
    /// runs unfolded (no `SwiftOperators.foldAll`), so the
    /// recognition is the raw three-element shape.
    fileprivate static func extractRangeBounds(
        _ expr: ExprSyntax,
        sourcePath: File.Path
    ) throws(Lint.File.Single.Error) -> (Swift.String, Swift.String)? {
        guard let sequence: SequenceExprSyntax = expr.as(SequenceExprSyntax.self) else {
            return nil
        }
        let elements: [ExprSyntax] = sequence.elements.map { $0 }
        guard elements.count == 3,
            let op: BinaryOperatorExprSyntax = elements[1].as(BinaryOperatorExprSyntax.self),
            op.operator.text == "..<"
        else {
            return nil
        }
        let lower: Swift.String = try Self.extractStringLiteral(elements[0], sourcePath: sourcePath)
        let upper: Swift.String = try Self.extractStringLiteral(elements[2], sourcePath: sourcePath)
        return (lower, upper)
    }

    /// Extract a `[String]` value from an `ArrayExprSyntax` whose
    /// elements are string literals.

    fileprivate static func extractStringArray(
        _ expr: ExprSyntax,
        sourcePath: File.Path
    ) throws(Lint.File.Single.Error) -> [Swift.String] {
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
    /// ``Lint/File/Single/Materializer/resolve(_:relativeTo:)``.
    /// `consumerPackageRoot` is canonicalized at the CLI boundary via
    /// ``Lint/File/Single/canonicalize(consumerRoot:currentWorkingDirectory:)``
    /// before reaching this site, so basename derivation receives an
    /// absolute path even when the CLI is invoked as `swift-linter .`.

    internal static func name(
        at path: Swift.String,
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
    /// Used by both `name(at:)` overloads for the
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

    internal static func name(at url: Swift.String) -> Swift.String {
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

    /// Parse a bare-string AST-extracted version literal into a
    /// typed ``Version/Semantic``.
    ///
    /// Delegates to `Version.Semantic(_:)` — the institute
    /// "throwing init indicates parsing" convention — which composes
    /// `swift-parser-primitives` internally and asserts the full
    /// string is consumed (non-ASCII detection + trailing-bytes
    /// check baked into the String adapter). Wraps the typed
    /// `Version.Semantic.Error` in a `malformedPackageCall` so the
    /// consumer sees a Lint-domain error with the parse-failure
    /// detail in `description`.
    ///
    /// `role` names the source position ("from", "range lower
    /// bound", "range upper bound") in the diagnostic.
    fileprivate static func parseSemantic(
        _ literal: Swift.String,
        sourcePath: File.Path,
        role: Swift.String
    ) throws(Lint.File.Single.Error) -> Version.Semantic {
        do throws(Version.Semantic.Error) {
            return try Version.Semantic(literal)
        } catch {
            throw .malformedPackageCall(
                path: sourcePath,
                description: "`.package(url:..., \(role) \"\(literal)\")` is not valid SemVer 2.0.0: \(error)"
            )
        }
    }

}
