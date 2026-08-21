public import Linter_Primitives

extension Lint.Suppression {

    public struct Entry: Sendable, Equatable {

        public let line: Text.Line.Number

        public let rule: Lint.Rule.ID

        public let reason: Swift.String?

        @inlinable
        public init(
            line: Text.Line.Number,
            rule: Lint.Rule.ID,
            reason: Swift.String? = nil
        ) {
            self.line = line
            self.rule = rule
            self.reason = reason
        }
    }
}
