import File_System
import Linter
import Testing

@testable import Linter_Core

extension Lint.Run {
  @Suite
  struct Test {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
    @Suite struct `Brand Pre-Pass` {}
  }
}

extension Lint.Rule {
  fileprivate static let `brand aware fixture` = Lint.Rule(
    id: "brand aware fixture",
    default: .warning,
    observe: Lint.Rule.measured { source, severity in
      if Lint.Brand.owned(["Cardinal"], in: source) { return [] }
      return [
        Diagnostic.Record(
          location: Source.Location(
            fileID: source.file.fileID,
            filePath: source.file.filePath,
            line: 1,
            column: 1
          ),
          severity: severity,
          identifier: "brand aware fixture",
          message: "brand aware fixture rule fired"
        )
      ]
    }
  )
}

extension Lint.Run.Test.`Brand Pre-Pass` {
  private static func fixtureRoot(
    _ name: Swift.String,
    testFile: Swift.String = #filePath
  ) throws(Paths.Path.Error) -> File.Path {
    var components: [Swift.String] =
      testFile
      .split(separator: "/", omittingEmptySubsequences: false)
      .map(Swift.String.init)
    _ = components.popLast()
    _ = components.popLast()
    components.append("Fixtures")
    components.append(name)
    return try File.Path(components.joined(separator: "/"))
  }

  @Test
  func `brand owner run self-suppresses across files`() throws(Lint.Run.Error) {

    let root = try! Self.fixtureRoot("brand-prepass-fixture")
    let configuration = Lint.Configuration {
      .enable(.`brand aware fixture`)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 0)
  }

  @Test
  func `consumer run without the brand still fires`() throws(Lint.Run.Error) {

    let root = try! Self.fixtureRoot("brand-consumer-fixture")
    let configuration = Lint.Configuration {
      .enable(.`brand aware fixture`)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 1)
  }
}

extension Lint.Rule {
  fileprivate static let `test fixture` = Lint.Rule(
    id: "test fixture",
    default: .warning,
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
          identifier: "test fixture",
          message: "fixture rule fired"
        )
      ]
    }
  )
}

extension Lint.Run.Test.Integration {

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
    components.append("path-filter-fixture")
    return try File.Path(components.joined(separator: "/"))
  }

  @Test
  func `paths .all yields findings for both A and B`() throws(Lint.Run.Error) {

    let root = try! Self.fixtureRoot()
    let configuration = Lint.Configuration {
      .enable(.`test fixture`, paths: .all)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 2)
  }

  @Test
  func `paths .including A yields finding for A only`() throws(Lint.Run.Error) {

    let root = try! Self.fixtureRoot()
    let configuration = Lint.Configuration {
      .enable(.`test fixture`, paths: .including(["Sources/A"]))
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 1)
    #expect(findings.first?.record.location.filePath?.hasSuffix("/Sources/A/x.swift") == true)
  }

  @Test
  func `paths .excluding B yields finding for A only`() throws(Lint.Run.Error) {

    let root = try! Self.fixtureRoot()
    let configuration = Lint.Configuration {
      .enable(.`test fixture`, paths: .excluding(["Sources/B"]))
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 1)
    #expect(findings.first?.record.location.filePath?.hasSuffix("/Sources/A/x.swift") == true)
  }

  @Test
  func `paths .including non-matching yields no findings`() throws(Lint.Run.Error) {

    let root = try! Self.fixtureRoot()
    let configuration = Lint.Configuration {
      .enable(.`test fixture`, paths: .including(["Tests/Fixtures/Other"]))
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)
    #expect(findings.count == 0)
  }
}
