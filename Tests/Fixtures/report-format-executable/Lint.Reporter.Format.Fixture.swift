import Linter

extension Lint.Rule {
  fileprivate static let `report format fixture` = Lint.Rule(
    id: "report format fixture",
    default: .error,
    controls: [
      .init(
        id: "report format fixture positive",
        source: "let value = 0",
        path: "Controls/ReportFormat.swift",
        expectation: .findings(1)
      )
    ],
    observe: Lint.Rule.measured { source, severity in
      [
        Diagnostic.Record(
          location: Source.Location(
            fileID: source.file.fileID,
            filePath: source.file.filePath,
            line: 1,
            column: 1
          ),
          severity: severity,
          identifier: "report format fixture",
          message: "fixture rule fired"
        )
      ]
    }
  )
}

Lint.run(bundles: [
  .primitives: [.enable(.`report format fixture`)]
])
