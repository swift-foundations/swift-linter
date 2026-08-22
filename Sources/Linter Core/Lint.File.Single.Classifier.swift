internal import Linter_Primitives
internal import Manifest_Primitives
internal import SwiftParser
internal import SwiftSyntax

extension Lint.File.Single {

  public enum Classifier {}
}

extension Lint.File.Single.Classifier {

  fileprivate static func bakedBundle(matching expression: ExprSyntax) -> Lint.Rule.Bundle.Baked? {
    guard expression.as(MemberAccessExprSyntax.self) != nil else { return nil }
    let text: Swift.String = expression.trimmedDescription
    return Lint.Rule.Bundle.Baked.allCases.first { $0.expression == text }
  }

  public static func classify(source: Swift.String) -> Lint.File.Single.Classification {
    Self.classify(source: source, parsed: Parser.parse(source: source))
  }

  internal static func classify(
    source: Swift.String,
    parsed sourceFile: SourceFileSyntax
  ) -> Lint.File.Single.Classification {

    if Manifest_Primitives.Manifest.Parent.scan(in: source) != nil {
      return .evalFallback(reason: "consumer declares a `// parent:` inheritance chain")
    }

    guard let runCall: FunctionCallExprSyntax = Lint.File.Single.Invocation.find(in: sourceFile)
    else {
      return .evalFallback(reason: "no top-level `Lint.run(...)` call expression")
    }
    guard let closure: ClosureExprSyntax = Self.ruleClosure(of: runCall) else {
      return .evalFallback(reason: "`Lint.run(...)` carries no rule-activation closure")
    }
    let statements: CodeBlockItemListSyntax = closure.statements
    guard statements.count == 1,
      let only: CodeBlockItemSyntax = statements.first,
      let expression: ExprSyntax = only.item.as(ExprSyntax.self)
    else {
      return .evalFallback(reason: "rule closure is not a single expression")
    }

    if let bundle: Lint.Rule.Bundle.Baked = Self.bakedBundle(matching: expression) {
      return .fastPathStandardBundle(bundle: bundle)
    }

    if let (bundle, disabled): (Lint.Rule.Bundle.Baked, Swift.Set<Lint.Rule.ID>) =
      Self.bakedBundleExclusions(expression)
    {
      return .fastPathStandardBundleExcluding(bundle: bundle, disabled: disabled)
    }
    return .evalFallback(
      reason: "rule closure is not a baked standard bundle nor `.excluding(rules:)` over one"
    )
  }

  fileprivate static func bakedBundleExclusions(
    _ expression: ExprSyntax
  ) -> (bundle: Lint.Rule.Bundle.Baked, disabled: Swift.Set<Lint.Rule.ID>)? {
    guard let call: FunctionCallExprSyntax = expression.as(FunctionCallExprSyntax.self),
      let member: MemberAccessExprSyntax = call.calledExpression.as(
        MemberAccessExprSyntax.self
      ),
      member.declName.baseName.text == "excluding",
      let base: ExprSyntax = member.base,
      let bundle: Lint.Rule.Bundle.Baked = Self.bakedBundle(matching: base)
    else {
      return nil
    }

    guard call.trailingClosure == nil,
      call.additionalTrailingClosures.isEmpty,
      call.arguments.count == 1,
      let argument: LabeledExprSyntax = call.arguments.first,
      argument.label?.text == "rules",
      let array: ArrayExprSyntax = argument.expression.as(ArrayExprSyntax.self)
    else {
      return nil
    }
    var ids: Swift.Set<Lint.Rule.ID> = []
    for element in array.elements {
      guard let id: Lint.Rule.ID = Self.extractRuleID(element.expression) else {
        return nil
      }
      ids.insert(id)
    }
    return ids.isEmpty ? nil : (bundle: bundle, disabled: ids)
  }

  fileprivate static func extractRuleID(_ expression: ExprSyntax) -> Lint.Rule.ID? {

    if let literal: StringLiteralExprSyntax = expression.as(StringLiteralExprSyntax.self) {
      guard literal.segments.count == 1,
        let segment: StringSegmentSyntax = literal.segments.first?.as(
          StringSegmentSyntax.self
        )
      else { return nil }
      return Lint.Rule.ID(segment.content.text)
    }

    if let outer: MemberAccessExprSyntax = expression.as(MemberAccessExprSyntax.self),
      outer.declName.baseName.text == "id",
      let inner: MemberAccessExprSyntax = outer.base?.as(MemberAccessExprSyntax.self)
    {
      let name: Swift.String = Self.unbacktick(inner.declName.baseName.text)
      return name.isEmpty ? nil : Lint.Rule.ID(name)
    }
    return nil
  }

  fileprivate static func unbacktick(_ text: Swift.String) -> Swift.String {
    var slice: Swift.Substring = text[...]
    if slice.first == "`" { slice = slice.dropFirst() }
    if slice.last == "`" { slice = slice.dropLast() }
    return Swift.String(slice)
  }

  fileprivate static func ruleClosure(of call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
    if let trailing: ClosureExprSyntax = call.trailingClosure {
      return trailing
    }
    for argument in call.arguments where argument.label?.text == "rules" {
      if let closure: ClosureExprSyntax = argument.expression.as(ClosureExprSyntax.self) {
        return closure
      }
    }
    return nil
  }
}
