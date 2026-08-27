import File_System
import JSON
import Linter
import Linter_Reporter_SARIF
import Linter_Reporter_Structured
import Linter_Reporter_Text
import Testing

@testable import Linter_Core

extension Lint.Run.Outcome {
  @Suite
  struct Test {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Run.Outcome.Test.Integration {
  @Test
  func `Structured report carries exact engine counts and repair evidence`() throws {
    let measured = Self.rule(id: "measured fixture", severity: .warning)
    let unmeasured = Lint.Rule(
      id: "unmeasured fixture",
      default: .warning,
      controls: [
        .init(
          id: "unmeasured fixture positive",
          source: "struct Fixture {}",
          path: "UnmeasuredFixture.swift",
          expectation: .clean
        )
      ],
      observe: { _, _ in
        Lint.Rule.Observation(
          findings: [],
          coverage: .unmeasured(.unsupportedSourceShape("fixture"))
        )
      }
    )
    let configuration = Lint.Configuration {
      Lint.Rule.Configuration.enable(measured)
      Lint.Rule.Configuration.enable(unmeasured)
    }
    let outcome = try Lint.Run.run(
      paths: [try Self.fixtureRoot()],
      capturing: .all,
      configuration: configuration
    )
    let document = try JSON.parse(Lint.Reporter.Structured.report(for: outcome))

    #expect(document.files.array?.count == outcome.files.count)
    #expect(document.activeRules.array?.count == 2)
    #expect(document.applicableRules.array?.count == 2)
    #expect(document.observations.array?.count == outcome.observations.count)
    #expect(document.findings.array?.count == outcome.findings.count)
    #expect(document.repairProposals.array?.count == outcome.repairs.count)
    #expect(Swift.String(document.summary.files) == Swift.String(outcome.summary.files))
    #expect(
      Swift.String(document.summary.activeRules)
        == Swift.String(outcome.summary.rules)
    )
    #expect(
      Swift.String(document.summary.unmeasuredObservations)
        == Swift.String(outcome.summary.unmeasured)
    )
    #expect(
      Swift.String(document.summary.findings) == Swift.String(outcome.summary.findings)
    )
  }

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
      controls: [
        .init(
          id: .init(_unchecked: id + " positive"),
          source: "struct Fixture {}",
          path: "Fixture.swift",
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

  @Test
  func `SARIF result count and violation-level subset match the engine's dual counts`() throws {
    let error = Self.rule(id: "count-contract error fixture", severity: .error)
    let warning = Self.rule(id: "count-contract warning fixture", severity: .warning)
    let note = Self.rule(id: "count-contract note fixture", severity: .note)
    let remark = Self.rule(id: "count-contract remark fixture", severity: .remark)
    let configuration = Lint.Configuration {
      Lint.Rule.Configuration.enable(error)
      Lint.Rule.Configuration.enable(warning)
      Lint.Rule.Configuration.enable(note)
      Lint.Rule.Configuration.enable(remark)
    }
    let outcome = try Lint.Run.run(
      paths: [try Self.fixtureRoot()],
      capturing: .all,
      configuration: configuration
    )

    #expect(outcome.findings.count == 4)
    #expect(outcome.violations.count == 2)

    let sarif = Lint.Reporter.SARIF.report(for: outcome.findings)
    let document: JSON
    do throws(JSON.Error) {
      document = try JSON.parse(sarif)
    } catch {
      Issue.record("SARIF report was not valid JSON: \(error)\n\(sarif)")
      return
    }
    guard let results = document.runs[0].results.array else {
      Issue.record("SARIF document carried no results array")
      return
    }

    #expect(results.count == outcome.findings.count)

    let violationLevels: Swift.Set<Swift.String> = ["error", "warning"]
    let sarifViolations = results.filter { violationLevels.contains(Swift.String($0.level)) }
    #expect(sarifViolations.count == outcome.violations.count)

    let line = Lint.Reporter.Text.Summary.line(
      package: "count-contract-fixture",
      activeRules: Cardinal(4),
      excludedRules: .zero,
      filesLinted: Cardinal(UInt(outcome.files.count)),
      violations: Cardinal(UInt(outcome.violations.count)),
      findings: Cardinal(UInt(outcome.findings.count))
    )
    #expect(line.contains("2 violations"))
    #expect(line.contains("4 findings"))
  }
}
