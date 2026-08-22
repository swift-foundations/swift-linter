extension Lint.Reporter.Format.Channel {

  public enum Error: Swift.Error, Hashable, Sendable {
    case invalid(value: Swift.String)
  }
}
