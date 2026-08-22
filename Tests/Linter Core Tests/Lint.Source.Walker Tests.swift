import File_System
import Linter_Primitives
import Testing

@testable import Linter_Core

extension Lint.Source.Walker {
  @Suite
  struct Test {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
    @Suite(.serialized) struct Performance {}
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

extension Lint.Source.Walker.Test {

  fileprivate static func fixtureRoot(
    testFile: Swift.String = #filePath
  ) throws(Paths.Path.Error) -> File.Path {
    var components: [Swift.String] =
      testFile
      .split(separator: "/", omittingEmptySubsequences: false)
      .map(Swift.String.init)
    _ = components.popLast()
    _ = components.popLast()
    components.append("Fixtures")
    components.append("nested-package-fixture")
    return try File.Path(components.joined(separator: "/"))
  }
}

extension Lint.Source.Walker.Test.Unit {
  @Test
  func `paths(under:) emits outer manifest and source but skips nested-package subtree`() {

    let root = try! Lint.Source.Walker.Test.fixtureRoot()
    let paths = Lint.Source.Walker.paths(under: root).map(\.underlying)
    #expect(
      paths == [
        "Package.swift",
        "Sources/Outer/x.swift",
      ]
    )
  }
}

extension Lint.Source.Walker.Test.Integration {
  @Test
  func `Lint.Run.run does not visit files inside a nested-package subtree`() throws(Lint.Run
    .Error)
  {

    let root = try! Lint.Source.Walker.Test.fixtureRoot()
    let configuration = Lint.Configuration {
      .enable(.`test fixture`, paths: .all)
    }
    let findings = try Lint.Run.run(paths: [root], configuration: configuration)

    #expect(findings.count == 2)
    let paths = Set(findings.compactMap(\.record.location.filePath))
    #expect(paths.contains(where: { $0.hasSuffix("/nested-package-fixture/Package.swift") }))
    #expect(paths.contains(where: { $0.hasSuffix("/Sources/Outer/x.swift") }))
    #expect(paths.allSatisfy { !$0.contains("/Experiments/inner/") })
  }
}
