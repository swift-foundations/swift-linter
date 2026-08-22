public import File_System
public import Linter_Primitives

extension Lint.Run {

  public struct Outcome: Sendable, Equatable {

    public let findings: [Lint.Finding]

    public let suppressed: [Lint.Finding]

    public let files: [File.Path]

    public let rules: [Lint.Rule.ID]

    public let observations: [Observation]

    public let repairs: [Repair.Proposal]

    public let controls: [Control.Evidence]

    @inlinable
    public init(
      findings: [Lint.Finding] = [],
      suppressed: [Lint.Finding] = [],
      files: [File.Path] = [],
      rules: [Lint.Rule.ID] = [],
      observations: [Observation] = [],
      repairs: [Repair.Proposal] = [],
      controls: [Control.Evidence] = []
    ) {
      self.findings = findings
      self.suppressed = suppressed
      self.files = files
      self.rules = rules
      self.observations = observations
      self.repairs = repairs
      self.controls = controls
    }
  }
}

extension Lint.Run.Outcome {
  @inlinable
  public var applicable: [Lint.Rule.ID] {
    rules.filter { rule in
      observations.contains { $0.rule == rule && $0.applicability.isApplicable }
    }
  }

  @inlinable
  public var summary: Lint.Run.Summary {
    Lint.Run.Summary(
      files: files.count,
      rules: rules.count,
      applicable: applicable.count,
      observations: observations.count { $0.applicability.isApplicable },
      measured: observations.count { $0.coverage == .measured },
      unmeasured: observations.count {
        if case .unmeasured = $0.coverage { true } else { false }
      },
      findings: findings.count,
      suppressed: suppressed.count,
      repairs: repairs.count
    )
  }

  public var violations: [Lint.Finding] {
    findings.filter { finding in
      switch finding.record.severity {
      case .error, .warning: true
      case .note, .remark: false
      }
    }
  }

  @inlinable
  public var failedControls: [Control.Evidence] {
    controls.filter { control in
      guard control.coverage == .measured else { return false }
      return control.actualFindings != control.expectation.count
    }
  }

  @inlinable
  public var unmeasuredControls: [Control.Evidence] {
    controls.filter {
      if case .unmeasured = $0.coverage { true } else { false }
    }
  }
}
