public import File_System
public import Linter_Primitives

extension Lint.Run {

  public struct Observation: Sendable, Equatable {

    public let file: File.Path

    public let rule: Lint.Rule.ID

    public let coverage: Lint.Rule.Coverage

    public let applicability: Lint.Rule.Observation.Applicability

    @inlinable
    public init(
      file: File.Path,
      rule: Lint.Rule.ID,
      coverage: Lint.Rule.Coverage,
      applicability: Lint.Rule.Observation.Applicability
    ) {
      self.file = file
      self.rule = rule
      self.coverage = coverage
      self.applicability = applicability
    }
  }
}
