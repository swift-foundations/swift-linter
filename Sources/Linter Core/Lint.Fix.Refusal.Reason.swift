extension Lint.Fix.Refusal {

    public enum Reason: Swift.Sendable, Swift.Equatable {

        case unparseable

        case manifestEvaluationFailed
    }
}

extension Lint.Fix.Refusal.Reason {

    public var summary: Swift.String {
        switch self {
        case .unparseable:
            "produced unparseable text"

        case .manifestEvaluationFailed:
            "produced a package manifest that does not evaluate"
        }
    }
}
