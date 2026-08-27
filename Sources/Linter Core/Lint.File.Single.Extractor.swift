public import File_System
public import Package
public import SPM_Standard
internal import SwiftParser
internal import SwiftSyntax
internal import Version

extension Lint.File.Single {

  public enum Extractor {}
}

extension Lint.File.Single.Extractor {

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

  internal static func dependencies(
    parsed sourceFile: SourceFileSyntax,
    sourcePath: File.Path,
    consumerPackageRoot: File.Path
  ) throws(Lint.File.Single.Error) -> [Package.Dependency] {
    guard let runCall: FunctionCallExprSyntax = Lint.File.Single.Invocation.find(in: sourceFile)
    else {
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
    guard let arrayExpr: ArrayExprSyntax = dependenciesArg.expression.as(ArrayExprSyntax.self)
    else {
      throw .dependenciesNotFound(
        path: sourcePath,
        description:
          "Lint.run(...) `dependencies:` argument is not a literal array; got `\(dependenciesArg.expression.description)`"
      )
    }
    var deps: [Package.Dependency] = []
    for element in arrayExpr.elements {
      guard
        let call: FunctionCallExprSyntax = element.expression.as(
          FunctionCallExprSyntax.self
        )
      else {
        throw .malformedPackageCall(
          path: sourcePath,
          description:
            "dependencies[] element is not a function call: `\(element.expression.description)`"
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

  fileprivate static func parsePackageCall(
    _ call: FunctionCallExprSyntax,
    sourcePath: File.Path,
    consumerPackageRoot: File.Path
  ) throws(Lint.File.Single.Error) -> Package.Dependency {
    guard
      let member: MemberAccessExprSyntax = call.calledExpression.as(
        MemberAccessExprSyntax.self
      ),
      member.declName.baseName.text == "package"
    else {
      throw .malformedPackageCall(
        path: sourcePath,
        description:
          "expected `.package(...)` call; got `\(call.calledExpression.description)`"
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

        if let (lower, upper) = try Self.extractRangeBounds(
          arg.expression,
          sourcePath: sourcePath
        ) {
          rangeBounds.append(lower)
          rangeBounds.append(upper)
        } else {
          let value: Swift.String = try Self.extractStringLiteral(
            arg.expression,
            sourcePath: sourcePath
          )
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
      do throws(Paths.Path.Error) {
        _ = try Paths.Path(pathString)
      } catch {
        throw .malformedPackageCall(
          path: sourcePath,
          description:
            "`.package(path:...)` carries an invalid path `\(pathString)`: \(error)"
        )
      }
      source = .path(pathString)
      derivedName = Self.name(at: pathString, consumerPackageRoot: consumerPackageRoot)
    } else if let urlString: Swift.String = urlArg {
      let url: URI
      do throws(URIError) {
        url = try URI(urlString)
      } catch {
        throw .malformedPackageCall(
          path: sourcePath,
          description:
            "`.package(url:...)` carries an invalid URI `\(urlString)`: \(error)"
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
          description:
            "`.package(url:...)` requires `from:`, `branch:`, or two positional version-range arguments; got `\(call.description)`"
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
        description:
          "string literal must be a single segment with no interpolation; got `\(literal.description)`"
      )
    }
    return segment.content.text
  }

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
      let value: Swift.String = try Self.extractStringLiteral(
        element.expression,
        sourcePath: sourcePath
      )
      result.append(value)
    }
    return result
  }

  internal static func name(
    at path: Swift.String,
    consumerPackageRoot: File.Path
  ) -> Swift.String {

    if path.isEmpty || path == "." {
      return consumerPackageRoot.components.last?.string ?? consumerPackageRoot.string
    }
    return basename(of: path)
  }

  private static func basename(of path: Swift.String) -> Swift.String {
    let typed: File.Path
    do throws(Paths.Path.Error) {
      typed = try File.Path(path)
    } catch {
      return path
    }
    return typed.components.last?.string ?? path
  }

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
        description:
          "`.package(url:..., \(role) \"\(literal)\")` is not valid SemVer 2.0.0: \(error)"
      )
    }
  }

}
