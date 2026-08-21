extension Lint.Fix.Exclusion.Channel {

    public enum Error: Swift.Error, Swift.Sendable {

        case unparseable(value: Swift.String, description: Swift.String)
    }
}
