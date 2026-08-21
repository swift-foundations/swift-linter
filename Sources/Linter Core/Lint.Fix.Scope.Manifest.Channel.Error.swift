extension Lint.Fix.Scope.Manifest.Channel {

    public enum Error: Swift.Error, Swift.Sendable {

        case unparseable(value: Swift.String, description: Swift.String)

        case invalid(path: Swift.String, description: Swift.String)
    }
}
