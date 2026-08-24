extension Lint.Profile {
  public struct Target: Hashable, Sendable {
    public let underlying: Swift.String
    public let sourceRoot: Lint.Filter.Prefix

    public init(
      _ underlying: Swift.String,
      sourceRoot: Swift.String
    ) throws(Lint.Profile.Error) {
      guard !underlying.isEmpty,
        underlying != ".", underlying != "..",
        !underlying.contains("/"), !underlying.contains("\\")
      else { throw .malformed("invalid applicability target \(underlying)") }
      let expected = "Sources/\(underlying)/"
      guard sourceRoot == expected else {
        throw .malformed(
          "applicability target \(underlying) must resolve to \(expected)"
        )
      }
      self.underlying = underlying
      self.sourceRoot = .init(sourceRoot)
    }
  }
}

extension Lint.Profile.Target {
  var sourcePrefix: Lint.Filter.Prefix {
    sourceRoot
  }
}
