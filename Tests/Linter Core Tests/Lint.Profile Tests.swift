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

  fileprivate static func rule(_ id: Swift.String) -> Lint.Rule.Configuration {
    .enable(
      .init(
        id: .init(id),
        default: .warning,
        observe: { _, _ in .init(findings: [], coverage: .measured) }
      )
    )
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
}
