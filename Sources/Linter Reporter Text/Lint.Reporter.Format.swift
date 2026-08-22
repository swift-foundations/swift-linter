public import Linter_Core

extension Lint.Reporter {

    public enum Format: Swift.String, Sendable, Hashable, CaseIterable {
        case text
        case sarif
        case structured
    }
}
