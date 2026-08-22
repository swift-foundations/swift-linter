internal import Environment

extension Lint.Run.Policy {

  public enum Channel {}
}

extension Lint.Run.Policy.Channel {

  public static let variable: Swift.String = "SWIFT_LINTER_EXIT_POLICY"

  public static func read() throws(Error) -> Lint.Run.Policy? {
    guard let raw: Swift.String = Environment.read(Self.variable) else {
      return nil
    }
    guard let policy: Lint.Run.Policy = Lint.Run.Policy(rawValue: raw) else {
      throw .invalid(value: raw)
    }
    return policy
  }
}
