import Linter

extension Lint.Rule {
    fileprivate static let `bundle fixture primitives` = Lint.Rule(
        id: "bundle fixture primitives",
        default: .error,
        findings: { source, severity in
            [
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.file.fileID,
                        filePath: source.file.filePath,
                        line: 1,
                        column: 1
                    ),
                    severity: severity,
                    identifier: "bundle fixture primitives",
                    message: "primitives bundle fired"
                )
            ]
        }
    )

    fileprivate static let `bundle fixture standards` = Lint.Rule(
        id: "bundle fixture standards",
        default: .error,
        findings: { source, severity in
            [
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.file.fileID,
                        filePath: source.file.filePath,
                        line: 1,
                        column: 1
                    ),
                    severity: severity,
                    identifier: "bundle fixture standards",
                    message: "standards bundle fired"
                )
            ]
        }
    )

    fileprivate static let `bundle fixture institute` = Lint.Rule(
        id: "bundle fixture institute",
        default: .error,
        findings: { source, severity in
            [
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.file.fileID,
                        filePath: source.file.filePath,
                        line: 1,
                        column: 1
                    ),
                    severity: severity,
                    identifier: "bundle fixture institute",
                    message: "institute bundle fired"
                )
            ]
        }
    )
}

Lint.run(bundles: [
    .primitives: [.enable(.`bundle fixture primitives`)],
    .standards: [.enable(.`bundle fixture standards`)],
    .institute: [.enable(.`bundle fixture institute`)],
])
