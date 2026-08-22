public import File_System
public import Linter_Primitives

extension Lint.Run.Repair {

  public struct Proposal: Sendable, Equatable {

    public let file: File.Path

    public let rule: Lint.Rule.ID

    public let proposal: Lint.Rule.Repair.Proposal

    @inlinable
    public init(
      file: File.Path,
      rule: Lint.Rule.ID,
      proposal: Lint.Rule.Repair.Proposal
    ) {
      self.file = file
      self.rule = rule
      self.proposal = proposal
    }
  }
}
