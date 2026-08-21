extension Lint.Fix {

    public enum Mode: Swift.String, Sendable, Hashable, CaseIterable {

        case apply

        case dryRun = "dry-run"
    }
}
