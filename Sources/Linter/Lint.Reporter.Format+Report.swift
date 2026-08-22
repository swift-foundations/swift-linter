public import Terminal_Primitives

extension Lint.Reporter.Format {

  public func emit(
    findings: [Lint.Finding],
    to write: Terminal.Stream.Write
  ) {
    switch self {
    case .text:
      Lint.Reporter.Text.emit(findings: findings, to: write)

    case .sarif:
      Lint.Reporter.SARIF.emit(findings: findings, to: write)

    case .structured:
      Lint.Reporter.Text.emit(
        text: Lint.Reporter.Structured.report(
          for: Lint.Run.Outcome(findings: findings)
        ),
        to: write
      )
    }
  }

  public func report(for findings: [Lint.Finding]) -> Swift.String {
    switch self {
    case .text:
      Lint.Reporter.Text.report(for: findings)

    case .sarif:
      Lint.Reporter.SARIF.report(for: findings)

    case .structured:
      Lint.Reporter.Structured.report(
        for: Lint.Run.Outcome(findings: findings)
      )
    }
  }
}
