public import JSON
public import Linter_Core

extension Lint.Reporter {

  public enum Structured {}
}

extension Lint.Reporter.Structured {

  public static func report(for outcome: Lint.Run.Outcome) -> Swift.String {
    document(for: outcome).serialize(pretty: false)
  }
}

extension Lint.Reporter.Structured {

  fileprivate static func document(for outcome: Lint.Run.Outcome) -> JSON {
    let summary = outcome.summary
    return JSON.object([
      ("schema", 2),
      ("files", .array(outcome.files.map { JSON(stringLiteral: $0.description) })),
      (
        "activeRules",
        .array(outcome.rules.map { JSON(stringLiteral: $0.underlying) })
      ),
      (
        "applicableRules",
        .array(outcome.applicable.map { JSON(stringLiteral: $0.underlying) })
      ),
      ("observations", .array(outcome.observations.map(observation))),
      ("findings", .array(outcome.findings.map(finding))),
      ("suppressions", .array(outcome.suppressed.map(finding))),
      ("repairProposals", .array(outcome.repairs.map(repairProposal))),
      ("controls", .array(outcome.controls.map(control))),
      (
        "summary",
        JSON.object([
          ("files", JSON(integerLiteral: summary.files)),
          ("activeRules", JSON(integerLiteral: summary.rules)),
          ("applicableRules", JSON(integerLiteral: summary.applicable)),
          (
            "applicableObservations",
            JSON(integerLiteral: summary.observations)
          ),
          ("measuredObservations", JSON(integerLiteral: summary.measured)),
          (
            "unmeasuredObservations",
            JSON(integerLiteral: summary.unmeasured)
          ),
          ("findings", JSON(integerLiteral: summary.findings)),
          ("suppressions", JSON(integerLiteral: summary.suppressed)),
          ("repairProposals", JSON(integerLiteral: summary.repairs)),
          ("controls", JSON(integerLiteral: outcome.controls.count)),
          ("failedControls", JSON(integerLiteral: outcome.failedControls.count)),
          (
            "unmeasuredControls",
            JSON(integerLiteral: outcome.unmeasuredControls.count)
          ),
        ])
      ),
    ])
  }

  fileprivate static func control(_ evidence: Lint.Run.Control.Evidence) -> JSON {
    let expectation: JSON
    switch evidence.expectation {
    case .clean:
      expectation = ["status": "clean"]
    case .findings(let count):
      expectation = JSON.object([
        ("status", "findings"),
        ("count", JSON(integerLiteral: count)),
      ])
    }
    return JSON.object([
      ("identity", JSON(stringLiteral: evidence.identity.underlying)),
      ("rule", JSON(stringLiteral: evidence.rule.underlying)),
      ("expectation", expectation),
      ("actualFindings", JSON(integerLiteral: evidence.actualFindings)),
      ("coverage", coverage(evidence.coverage)),
    ])
  }

  fileprivate static func observation(_ observation: Lint.Run.Observation) -> JSON {
    JSON.object([
      ("file", JSON(stringLiteral: observation.file.description)),
      ("rule", JSON(stringLiteral: observation.rule.underlying)),
      ("applicable", JSON(booleanLiteral: observation.applicability.isApplicable)),
      ("coverage", coverage(observation.coverage)),
    ])
  }

  fileprivate static func coverage(_ coverage: Lint.Rule.Coverage) -> JSON {
    switch coverage {
    case .measured:
      ["status": "measured"]
    case .unmeasured(let reason):
      JSON.object([
        ("status", "unmeasured"),
        ("reason", Self.reason(reason)),
      ])
    }
  }

  fileprivate static func finding(_ finding: Lint.Finding) -> JSON {
    let record = finding.record
    var fields: [(Swift.String, JSON)] = [
      ("rule", JSON(stringLiteral: record.identifier)),
      ("severity", JSON(stringLiteral: record.severity.wire.token)),
      ("message", JSON(stringLiteral: record.message)),
      ("fileID", JSON(stringLiteral: record.location.fileID)),
      ("line", JSON(integerLiteral: Int(record.location.line.underlying))),
      ("column", JSON(integerLiteral: Int(bitPattern: record.location.column))),
    ]
    if let path = record.location.filePath {
      fields.append(("filePath", JSON(stringLiteral: path)))
    }
    if let visibility = finding.visibility {
      fields.append(("visibility", JSON(stringLiteral: visibility.rawValue)))
    }
    return JSON.object(fields)
  }

  fileprivate static func repairProposal(_ proposal: Lint.Run.Repair.Proposal) -> JSON {
    JSON.object([
      ("file", JSON(stringLiteral: proposal.file.description)),
      ("rule", JSON(stringLiteral: proposal.rule.underlying)),
      ("proposal", repair(proposal.proposal)),
    ])
  }

  fileprivate static func repair(_ proposal: Lint.Rule.Repair.Proposal) -> JSON {
    switch proposal {
    case .unchanged:
      ["status": "unchanged"]
    case .refused(let reason):
      JSON.object([
        ("status", "refused"),
        ("reason", Self.reason(reason)),
      ])
    case .edits(let edits):
      JSON.object([
        ("status", "edits"),
        ("edits", .array(edits.map(edit))),
      ])
    }
  }

  fileprivate static func edit(_ edit: Lint.Rule.Repair.Edit) -> JSON {
    switch edit {
    case .rewrite(let path, let contents):
      JSON.object([
        ("operation", "rewrite"),
        ("path", JSON(stringLiteral: path.underlying)),
        ("contents", JSON(stringLiteral: contents)),
      ])
    case .create(let path, let contents):
      JSON.object([
        ("operation", "create"),
        ("path", JSON(stringLiteral: path.underlying)),
        ("contents", JSON(stringLiteral: contents)),
      ])
    case .move(let from, let to):
      JSON.object([
        ("operation", "move"),
        ("from", JSON(stringLiteral: from.underlying)),
        ("to", JSON(stringLiteral: to.underlying)),
      ])
    case .delete(let path):
      JSON.object([
        ("operation", "delete"),
        ("path", JSON(stringLiteral: path.underlying)),
      ])
    }
  }

  fileprivate static func reason(_ reason: Lint.Rule.Reason) -> JSON {
    switch reason {
    case .missingSemanticContext:
      ["code": "missingSemanticContext"]
    case .unsupportedSourceShape(let detail):
      JSON.object([
        ("code", "unsupportedSourceShape"),
        ("detail", JSON(stringLiteral: detail)),
      ])
    case .repairUnavailable:
      ["code": "repairUnavailable"]
    case .ambiguousRepair(let detail):
      JSON.object([
        ("code", "ambiguousRepair"),
        ("detail", JSON(stringLiteral: detail)),
      ])
    case .other(let code, let detail):
      JSON.object([
        ("code", JSON(stringLiteral: code)),
        ("detail", JSON(stringLiteral: detail)),
      ])
    }
  }
}
