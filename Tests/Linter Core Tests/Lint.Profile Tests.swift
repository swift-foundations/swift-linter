import File_System
import Linter_Primitives
import Testing

@testable import Linter

extension Lint.Profile {
  @Suite
  struct Test {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Profile.Test.Unit {
  @Test
  func `explicit profile selects the complete baked inventory`() throws {
    let known = Self.rule("known")
    let other = Self.rule("other")
    let profile = try Lint.Profile(
      revision: "revision",
      bundle: .institute,
      rules: [known.rule.id, other.rule.id]
    )

    #expect(
      try profile.select(from: [known, other]).map(\.rule.id)
        == [known.rule.id, other.rule.id]
    )
  }

  @Test
  func `schema two parses and applies a neutral declared target`() throws {
    let known = Self.rule("known")
    let profile = try Self.read(
      key: "schema-two",
      applicability: """
        [{"rule":"known","excludedTargets":[{"identity":"Declared Standard","sourceRoot":"Sources/Declared Standard/"}]}]
        """
    )

    let selected = try profile.select(from: [known])
    #expect(selected.count == 1)
    #expect(selected[0].rule.controls.count == known.rule.controls.count + 4)

    let root = try Self.fixtureRoot()
    let outcome = try Lint.Run.run(
      paths: [root],
      capturing: .all,
      configuration: Lint.Configuration { selected }
    )
    #expect(outcome.failedControls.isEmpty)
    #expect(outcome.unmeasuredControls.isEmpty)
  }

  fileprivate static func rule(_ id: Swift.String) -> Lint.Rule.Configuration {
    .enable(
      .init(
        id: .init(id),
        default: .warning,
        controls: [
          .init(
            id: .init("\(id) fires"),
            source: "public func twoWords() {}",
            path: "Sources/Ordinary/Fixture.swift",
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
              message: "fixture rule fired"
            )
          ]
        }
      )
    )
  }

  fileprivate static func read(
    key: Swift.String,
    applicability: Swift.String
  ) throws -> Lint.Profile {
    let path = try File.Path.Temporary.deterministic(
      prefix: "lint-profile-",
      key: key,
      suffix: ".json"
    )
    try File(path).write.atomic(
      """
      {"schema":2,"revision":"revision","bundle":"institute","applicability":\(applicability),"rules":["known"]}
      """
    )
    return try Lint.Profile.read(at: path.description)
  }

  fileprivate static func fixtureRoot(
    testFile: Swift.String = #filePath
  ) throws(Paths.Path.Error) -> File.Path {
    var components = testFile.split(
      separator: "/",
      omittingEmptySubsequences: false
    ).map(Swift.String.init)
    _ = components.popLast()
    _ = components.popLast()
    components.append("Fixtures")
    components.append("path-filter-fixture")
    return try File.Path(components.joined(separator: "/"))
  }
}

extension Lint.Profile.Test.`Edge Case` {
  @Test
  func `explicit profile refuses zero rules`() {
    #expect(throws: Lint.Profile.Error.self) {
      try Lint.Profile(revision: "revision", bundle: .institute, rules: [])
    }
  }

  @Test
  func `explicit profile refuses unknown rules`() throws {
    let profile = try Lint.Profile(
      revision: "revision",
      bundle: .institute,
      rules: [.init("unknown")]
    )

    #expect(throws: Lint.Profile.Error.self) {
      try profile.select(from: [])
    }
  }

  @Test
  func `explicit profile refuses a strict subset of its baked inventory`() throws {
    let known = Lint.Profile.Test.Unit.rule("known")
    let other = Lint.Profile.Test.Unit.rule("other")
    let profile = try Lint.Profile(
      revision: "revision",
      bundle: .institute,
      rules: [known.rule.id]
    )

    #expect(throws: Lint.Profile.Error.self) {
      try profile.select(from: [known, other])
    }
  }

  @Test
  func `schema two refuses a malformed target resolution`() {
    #expect(throws: Lint.Profile.Error.self) {
      try Lint.Profile.Test.Unit.read(
        key: "malformed-target",
        applicability: """
          [{"rule":"known","excludedTargets":[{"identity":"Declared Standard","sourceRoot":"Sources/Other/"}]}]
          """
      )
    }
  }

  @Test
  func `schema two refuses a duplicate target identity`() {
    #expect(throws: Lint.Profile.Error.self) {
      try Lint.Profile.Test.Unit.read(
        key: "duplicate-target",
        applicability: """
          [{"rule":"known","excludedTargets":[{"identity":"Declared Standard","sourceRoot":"Sources/Declared Standard/"},{"identity":"Declared Standard","sourceRoot":"Sources/Declared Standard/"}]}]
          """
      )
    }
  }
}
