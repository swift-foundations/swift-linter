internal import Environment

extension Lint.Rule.Bundle.Baked {

  public enum Channel {}
}

extension Lint.Rule.Bundle.Baked.Channel {

  public static let variable: Swift.String = "SWIFT_LINTER_BUNDLE"

  public static func read() throws(Error) -> Lint.Rule.Bundle.Baked? {
    guard let raw: Swift.String = Environment.read(Self.variable) else {
      return nil
    }
    guard let bundle: Lint.Rule.Bundle.Baked = Lint.Rule.Bundle.Baked(rawValue: raw) else {
      throw .invalid(value: raw)
    }
    return bundle
  }
}
