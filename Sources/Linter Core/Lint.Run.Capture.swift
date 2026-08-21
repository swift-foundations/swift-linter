extension Lint.Run {

    public enum Capture: Swift.String, Sendable, Hashable, CaseIterable {
        case findings
        case suppressed
        case all
    }
}
