public import Linter_Primitives

extension Lint.Rule.Bundle {

  public enum Baked: Swift.String, Swift.CaseIterable, Swift.Sendable {

    case primitives

    case standards

    case institute
  }
}

extension Lint.Rule.Bundle.Baked {

  public var token: Swift.String { rawValue }

  public var expression: Swift.String {
    "Lint.Rule.Bundle.\(token)"
  }
}
