extension Lint.Profile {
  public enum Error: Swift.Error, Sendable {
    case path(Swift.String)
    case read(Swift.String)
    case malformed(Swift.String)
    case schema(Swift.Int)
    case bundle(Swift.String)
    case rules(Swift.String)
  }
}
