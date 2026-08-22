import Environment
import Linter
import Testing

@testable import Linter_Core

extension Lint.File.Single.Test {
  @Suite
  struct Runner {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.File.Single.Test.Runner.Unit {
  @Test
  func `Multi-path arguments are forwarded verbatim after the binary`() {
    let invocation = Lint.File.Single.Runner.invocation(
      binary: "/usr/local/bin/swift-linter-runner",
      arguments: ["Sources", "Tests"]
    )
    #expect(invocation == ["/usr/local/bin/swift-linter-runner", "Sources", "Tests"])
  }

  @Test
  func `A single dot target is forwarded`() {
    let invocation = Lint.File.Single.Runner.invocation(
      binary: "runner",
      arguments: ["."]
    )
    #expect(invocation == ["runner", "."])
  }

  @Test
  func `Empty arguments yield just the binary (Lint.run applies its dot default)`() {

    let invocation = Lint.File.Single.Runner.invocation(
      binary: "runner",
      arguments: []
    )
    #expect(invocation == ["runner"])
  }
}

extension Lint.File.Single.Test.Runner.Unit {
  @Test
  func `SARIF selection survives the prebuilt runner environment boundary`() {
    let environment = Lint.File.Single.Runner.environment(
      inheriting: Environment.Snapshot([
        Lint.Reporter.Format.Channel.variable:
          Lint.Reporter.Format.Channel.value(.sarif)
      ]),
      bundle: .primitives,
      selection: nil
    )
    #expect(
      environment[Lint.Reporter.Format.Channel.variable]
        == Lint.Reporter.Format.Channel.value(.sarif)
    )
  }

  @Test
  func `Runner overlays do not replace an explicitly selected text format`() {
    let environment = Lint.File.Single.Runner.environment(
      inheriting: Environment.Snapshot([
        Lint.Reporter.Format.Channel.variable:
          Lint.Reporter.Format.Channel.value(.text)
      ]),
      bundle: .standards,
      selection: nil
    )
    #expect(
      environment[Lint.Reporter.Format.Channel.variable]
        == Lint.Reporter.Format.Channel.value(.text)
    )
  }

  @Test
  func `Runner adds its bundle without dropping unrelated channels`() {
    let environment = Lint.File.Single.Runner.environment(
      inheriting: Environment.Snapshot(["SWIFT_LINTER_TEST_SENTINEL": "preserved"]),
      bundle: .institute,
      selection: nil
    )
    #expect(environment["SWIFT_LINTER_TEST_SENTINEL"] == "preserved")
    #expect(
      environment[Lint.Rule.Bundle.Baked.Channel.variable]
        == Lint.Rule.Bundle.Baked.institute.rawValue
    )
  }
}
