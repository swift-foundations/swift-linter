public import Linter_Primitives

extension Lint.Run {

    public enum Policy: Swift.String, Sendable, Hashable, CaseIterable {
        case advisory
        case strict
    }
}

extension Lint.Run.Policy {

    public var token: Swift.String {
        switch self {
        case .advisory: "advisory"
        case .strict: "strict"
        }
    }

    public func fails(for findings: [Lint.Finding]) -> Swift.Bool {
        switch self {
        case .advisory: false

        case .strict:
            findings.contains { $0.record.severity == .error }
        }
    }
}
