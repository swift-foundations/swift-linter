import File_System
import SPM_Standard
import Testing

@testable import Linter_Core

extension Lint.File.Single.Extractor {
  @Suite
  struct Test {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
    @Suite struct Name {}
  }
}

extension Lint.File.Single {
  @Suite
  struct Test {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
    @Suite struct Canonicalize {}
  }
}

extension Lint.File.Single.Test.Canonicalize {
  @Test
  func `Dot consumerRoot resolves via cwd closure`() {
    let resolved = Lint.File.Single.canonicalize(
      consumerRoot: ".",
      currentWorkingDirectory: { "/workspace/swift-cardinal" }
    )
    #expect(resolved == "/workspace/swift-cardinal")
  }

  @Test
  func `Empty consumerRoot resolves via cwd closure`() {
    let resolved = Lint.File.Single.canonicalize(
      consumerRoot: "",
      currentWorkingDirectory: { "/workspace/swift-cardinal" }
    )
    #expect(resolved == "/workspace/swift-cardinal")
  }

  @Test
  func `Absolute path is returned unchanged`() {
    let resolved = Lint.File.Single.canonicalize(
      consumerRoot: "/workspace/swift-cardinal",
      currentWorkingDirectory: { "/workspace/elsewhere" }
    )
    #expect(resolved == "/workspace/swift-cardinal")
  }

  @Test
  func `Relative non-self path is returned unchanged`() {
    let resolved = Lint.File.Single.canonicalize(
      consumerRoot: "./Sources",
      currentWorkingDirectory: { "/workspace/elsewhere" }
    )
    #expect(resolved == "./Sources")
  }

  @Test
  func `Dot consumerRoot with cwd unavailable falls back to dot`() {

    let resolved = Lint.File.Single.canonicalize(
      consumerRoot: ".",
      currentWorkingDirectory: { nil }
    )
    #expect(resolved == ".")
  }
}

extension Lint.File.Single.Extractor.Test.Name {
  @Test
  func `Sibling-package relative path uses path's own basename`() {
    let name = Lint.File.Single.Extractor.name(
      at: "../swift-primitives-linter-rules",
      consumerPackageRoot: File.Path(
        stringLiteral: "/workspace/swift-molecules/swift-cardinal"
      )
    )
    #expect(name == "swift-primitives-linter-rules")
  }

  @Test
  func `Absolute path uses path's own basename`() {
    let name = Lint.File.Single.Extractor.name(
      at: "/workspace/swift-compositions/swift-linter-rules",
      consumerPackageRoot: File.Path(
        stringLiteral: "/workspace/swift-molecules/swift-cardinal"
      )
    )
    #expect(name == "swift-linter-rules")
  }

  @Test
  func `Self-reference dot derives package name from consumer-root basename`() {
    let name = Lint.File.Single.Extractor.name(
      at: ".",
      consumerPackageRoot: File.Path(
        stringLiteral: "/workspace/swift-molecules/swift-cardinal"
      )
    )
    #expect(name == "swift-cardinal")
  }

  @Test
  func `Self-reference empty string derives package name from consumer-root basename`() {
    let name = Lint.File.Single.Extractor.name(
      at: "",
      consumerPackageRoot: File.Path(
        stringLiteral: "/workspace/swift-molecules/swift-cardinal"
      )
    )
    #expect(name == "swift-cardinal")
  }

  @Test
  func `Self-reference dot strips trailing slash from consumer-root`() {
    let name = Lint.File.Single.Extractor.name(
      at: ".",
      consumerPackageRoot: File.Path(
        stringLiteral: "/workspace/swift-molecules/swift-cardinal/"
      )
    )
    #expect(name == "swift-cardinal")
  }
}

extension Lint.File.Single.Extractor.Test {
  @Test
  func `path dependency preserves SwiftPM path string`() throws(Lint.File.Single.Error) {
    let dependencies = try Lint.File.Single.Extractor.dependencies(
      from: """
        Lint.run(
            dependencies: [
                .package(path: "../swift-linter-rules", products: ["Linter Rules"]),
            ]
        ) {}
        """,
      sourcePath: File.Path(stringLiteral: "/tmp/Lint.swift"),
      consumerPackageRoot: File.Path(stringLiteral: "/tmp/consumer")
    )

    #expect(dependencies.count == 1)
    #expect(dependencies.first?.source == .path("../swift-linter-rules"))
  }
}
