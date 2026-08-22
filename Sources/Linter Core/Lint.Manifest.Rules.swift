public import Linter_Primitives

extension Lint.Manifest {

  public struct Rules: Sendable, Hashable {

    public let enabled: Set<Lint.Rule.ID>

    public let disabled: Set<Lint.Rule.ID>

    public init(
      enabled: Set<Lint.Rule.ID> = [],
      disabled: Set<Lint.Rule.ID> = []
    ) {
      self.enabled = enabled
      self.disabled = disabled
    }
  }
}
