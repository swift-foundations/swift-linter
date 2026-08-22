extension Lint.Run.Observation {
    public enum Applicability: Sendable, Equatable {
        case applicable
        case inapplicable
    }
}

extension Lint.Run.Observation.Applicability {
    @inlinable
    public var isApplicable: Swift.Bool { self == .applicable }
}
