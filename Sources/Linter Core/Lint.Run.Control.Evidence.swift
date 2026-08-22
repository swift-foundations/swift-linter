public import Linter_Primitives

extension Lint.Run.Control {
  public struct Evidence: Equatable, Sendable {
    public let identity: Lint.Rule.Control.ID
    public let rule: Lint.Rule.ID
    public let expectation: Lint.Rule.Control.Expectation
    public let actualFindings: Swift.Int
    public let coverage: Lint.Rule.Coverage

    @inlinable
    public init(
      identity: Lint.Rule.Control.ID,
      rule: Lint.Rule.ID,
      expectation: Lint.Rule.Control.Expectation,
      actualFindings: Swift.Int,
      coverage: Lint.Rule.Coverage
    ) {
      self.identity = identity
      self.rule = rule
      self.expectation = expectation
      self.actualFindings = actualFindings
      self.coverage = coverage
    }
  }
}
