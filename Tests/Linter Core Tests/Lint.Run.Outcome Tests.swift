// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-linter open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-linter project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

import File_System
import Linter_Primitives
import Linter_Reporter_Text
import Testing

@testable import Linter_Core

extension Lint.Run.Outcome {
    @Suite
    struct Test {
        @Suite struct Integration {}
    }
}

extension Lint.Run.Outcome.Test.Integration {
    private static func fixtureRoot(
        testFile: Swift.String = #filePath
    ) throws(Paths.Path.Error) -> File.Path {
        var components: [Swift.String] =
            testFile
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(Swift.String.init)
        _ = components.popLast()
        _ = components.popLast()
        components.append("Fixtures")
        components.append("brand-consumer-fixture")
        return try File.Path(components.joined(separator: "/"))
    }

    private static func rule(
        id: Swift.String,
        severity: Diagnostic.Severity
    ) -> Lint.Rule {
        Lint.Rule(
            id: Lint.Rule.ID(_unchecked: id),
            default: severity,
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
                        identifier: id,
                        message: "fixture finding"
                    )
                ]
            }
        )
    }

    @Test
    func `errors and warnings count while notes remain rendered prompts`() throws {
        let error = Self.rule(id: "error fixture", severity: .error)
        let warning = Self.rule(id: "warning fixture", severity: .warning)
        let prompt = Self.rule(id: "prompt fixture", severity: .note)
        let configuration = Lint.Configuration {
            Lint.Rule.Configuration.enable(error)
            Lint.Rule.Configuration.enable(warning)
            Lint.Rule.Configuration.enable(prompt)
        }
        let outcome = try Lint.Run.run(
            paths: [try Self.fixtureRoot()],
            capturing: .all,
            configuration: configuration
        )

        #expect(outcome.findings.count == 3)
        #expect(outcome.violations.count == 2)
        #expect(outcome.violations.allSatisfy { $0.record.severity != Diagnostic.Severity.note })

        let rendered = Lint.Reporter.Text.report(for: outcome.findings)
        #expect(rendered.contains("error: error fixture: fixture finding"))
        #expect(rendered.contains("warning: warning fixture: fixture finding"))
        #expect(rendered.contains("note: prompt fixture: fixture finding"))

        #expect(Lint.Run.Policy.strict.fails(for: outcome.findings))
        let nonErrors = outcome.findings.filter { $0.record.severity != Diagnostic.Severity.error }
        #expect(!Lint.Run.Policy.strict.fails(for: nonErrors))
        #expect(!Lint.Run.Policy.advisory.fails(for: outcome.findings))
    }
}
