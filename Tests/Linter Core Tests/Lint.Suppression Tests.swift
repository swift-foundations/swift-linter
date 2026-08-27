import File_System
import Foundation
import Linter
import SwiftParser
import SwiftSyntax
import Testing

@testable import Linter_Core

extension Lint.Suppression {
  @Suite
  struct Test {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
    @Suite struct Scanner {}
    @Suite struct `Engine Integration` {}
  }
}

extension Lint.Suppression.Test.Scanner {

  private static func scanSource(
    _ source: Swift.String,
    fileName: Swift.String = "<test>"
  ) -> Lint.Suppression {
    let tree = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: fileName, tree: tree)
    return Lint.Suppression.scan(tree: tree, converter: converter)
  }

  @Test
  func `Empty source yields empty suppression map`() {
    let map = Self.scanSource("")
    #expect(map.entries.isEmpty)
  }

  @Test
  func `Source with no directives yields empty suppression map`() {
    let source = """
      let x = 1
      let y = 2
      """
    let map = Self.scanSource(source)
    #expect(map.entries.isEmpty)
  }

  @Test
  func `disable next directive suppresses the immediately following code line`() {

    let source = """
      // swift-linter:disable:next some rule
      let x = 1
      """
    let map = Self.scanSource(source)
    #expect(map.entries.count == 1)
    let entry = map.entries.first
    #expect(entry?.line == 2)
    #expect(entry?.rule.underlying == "some rule")
  }

  @Test
  func `disable next directive skips blank lines to next non-blank line`() {

    let source = """
      // swift-linter:disable:next some rule

      let x = 1
      """
    let map = Self.scanSource(source)
    #expect(map.entries.count == 1)
    #expect(map.entries.first?.line == 3)
  }

  @Test
  func `disable line directive suppresses the line carrying the directive`() {

    let source = """
      let x = 1 // swift-linter:disable:line some rule
      let y = 2
      """
    let map = Self.scanSource(source)
    #expect(map.entries.count == 1)
    #expect(map.entries.first?.line == 1)
    #expect(map.entries.first?.rule.underlying == "some rule")
  }

  @Test
  func `disable next with REASON continuation captures reason prose`() {
    let source = """
      // swift-linter:disable:next some rule
      // REASON: this site is the typed-system bottom-out per [CONV-016].
      let x = 1
      """
    let map = Self.scanSource(source)
    #expect(map.entries.count == 1)
    #expect(map.entries.first?.line == 3)
    #expect(map.entries.first?.reason?.contains("typed-system bottom-out") == true)
  }

  @Test
  func `multiple disable directives produce independent entries`() {
    let source = """
      // swift-linter:disable:next rule one
      let a = 1
      // swift-linter:disable:next rule two
      let b = 2
      """
    let map = Self.scanSource(source)
    #expect(map.entries.count == 2)

    #expect(map.entries.contains { $0.line == 2 && $0.rule.underlying == "rule one" })
    #expect(map.entries.contains { $0.line == 4 && $0.rule.underlying == "rule two" })
  }

  @Test
  func `suppresses returns true only for matching line and rule ID`() {
    let map = Lint.Suppression(entries: [
      Lint.Suppression.Entry(line: 5, rule: "rule one", reason: nil)
    ])
    #expect(map.suppresses(line: 5, rule: "rule one"))
    #expect(!map.suppresses(line: 5, rule: "rule two"))
    #expect(!map.suppresses(line: 6, rule: "rule one"))
  }
}

extension Lint.Rule {
  fileprivate static let `suppression fixture` = Lint.Rule(
    id: "suppression fixture",
    default: .warning,
    observe: Lint.Rule.measured { source, severity in

      let visitor = LintSuppressionFixtureVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter
      )
      visitor.walk(source.tree)
      return visitor.matches
    }
  )
}

internal final class LintSuppressionFixtureVisitor: SyntaxVisitor {
  let source: Source.File
  let severity: Diagnostic.Severity
  let converter: SourceLocationConverter
  var matches: [Diagnostic.Record] = []

  init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
    self.source = source
    self.severity = severity
    self.converter = converter
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
    guard node.text == "targetCall" else { return .visitChildren }
    let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
    matches.append(
      Diagnostic.Record(
        location: Source.Location(
          fileID: source.fileID,
          filePath: source.filePath,
          line: location.line,
          column: location.column
        ),
        severity: severity,
        identifier: "suppression fixture",
        message: "fixture rule fired"
      )
    )
    return .visitChildren
  }
}

extension Lint.Suppression.Test.`Engine Integration` {

  private static func writeFixture(content: Swift.String) -> File.Path {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lint-suppression-fixture-\(UUID().uuidString)"
    )
    let sources = directory.appendingPathComponent("Sources")

    try! FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    let file = sources.appendingPathComponent("x.swift")

    try! content.data(using: .utf8)!.write(to: file)

    return try! File.Path(directory.path)
  }

  @Test
  func `without directive, the fixture rule fires`() throws(Lint.Run.Error) {

    let root = Self.writeFixture(
      content: """
        targetCall()
        let _ = 0
        """
    )
    let configuration = Lint.Configuration {
      .enable(.`suppression fixture`)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 1)
  }

  @Test
  func `disable next elides the next-line finding`() throws(Lint.Run.Error) {

    let root = Self.writeFixture(
      content: """
        // swift-linter:disable:next suppression fixture
        targetCall()
        """
    )
    let configuration = Lint.Configuration {
      .enable(.`suppression fixture`)
    }
    let outcome = try Lint.Run.run(paths: [root], capturing: .all, configuration: configuration)
    #expect(outcome.findings.isEmpty)
    #expect(outcome.suppressed.count == 1)
  }

  @Test
  func `disable line elides the same-line finding`() throws(Lint.Run.Error) {

    let root = Self.writeFixture(
      content: """
        targetCall() // swift-linter:disable:line suppression fixture
        """
    )
    let configuration = Lint.Configuration {
      .enable(.`suppression fixture`)
    }
    let outcome = try Lint.Run.run(paths: [root], capturing: .all, configuration: configuration)
    #expect(outcome.findings.isEmpty)
    #expect(outcome.suppressed.count == 1)
  }

  @Test
  func `disable next with mismatched rule ID does not elide finding`() throws(Lint.Run.Error) {

    let root = Self.writeFixture(
      content: """
        // swift-linter:disable:next other rule
        targetCall()
        """
    )
    let configuration = Lint.Configuration {
      .enable(.`suppression fixture`)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 1)
  }

  @Test
  func `Configuration rules disabled elides all findings for that rule`() throws(Lint.Run.Error) {

    let root = Self.writeFixture(
      content: """
        targetCall()
        targetCall()
        """
    )
    let configuration = Lint.Configuration(
      disabled: ["suppression fixture"]
    ) {
      .enable(.`suppression fixture`)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.isEmpty)
  }

  @Test
  func `Manifest disabledRuleIDs threads through Driver to Configuration rules disabled`() {

    let manifest = Lint.Manifest(
      disabled: ["suppression fixture"]
    )
    let configuration = Lint.Driver.configuration(from: manifest, parent: nil)
    #expect(configuration.rules.disabled.contains("suppression fixture"))
  }

  @Test
  func `Engine tags findings with the enclosing decl's effective visibility`() throws(Lint.Run
    .Error)
  {

    let root = Self.writeFixture(
      content: """
        private struct Outer {
            func body() { targetCall() }
        }
        """
    )
    let configuration = Lint.Configuration {
      .enable(.`suppression fixture`)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 1)
    #expect(findings.first?.visibility == .private)
  }

  @Test
  func `Top-level finding is tagged internal by default`() throws(Lint.Run.Error) {

    let root = Self.writeFixture(
      content: """
        targetCall()
        """
    )
    let configuration = Lint.Configuration {
      .enable(.`suppression fixture`)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 1)
    #expect(findings.first?.visibility == .internal)
  }
}
