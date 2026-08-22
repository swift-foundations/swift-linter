public import Linter_Primitives

extension Lint.File.Single {

  public enum Classification: Swift.Sendable, Swift.Equatable {

    case fastPathStandardBundle(bundle: Lint.Rule.Bundle.Baked)

    case fastPathStandardBundleExcluding(
      bundle: Lint.Rule.Bundle.Baked,
      disabled: Swift.Set<Lint.Rule.ID>
    )

    case evalFallback(reason: Swift.String)
  }
}
