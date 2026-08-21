public import Linter_Primitives

extension Lint.Reporter {

    public enum Format: Swift.String, Sendable, Hashable, CaseIterable {
        case text
        case sarif
        case structured
    }
}
