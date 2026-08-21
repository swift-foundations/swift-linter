public import File_System
public import Linter_Primitives

extension Lint.Fix {

    public struct Change: Sendable, Equatable {

        public let path: File.Path

        public let rules: [Lint.Rule.ID]

        public let original: Swift.String

        public let fixed: Swift.String

        @inlinable
        public init(
            path: File.Path,
            rules: [Lint.Rule.ID],
            original: Swift.String,
            fixed: Swift.String
        ) {
            self.path = path
            self.rules = rules
            self.original = original
            self.fixed = fixed
        }
    }
}

extension Lint.Fix {

    public struct Refusal: Sendable, Equatable {

        public let path: File.Path

        public let rule: Lint.Rule.ID

        public let reason: Reason

        @inlinable
        public init(path: File.Path, rule: Lint.Rule.ID, reason: Reason = .unparseable) {
            self.path = path
            self.rule = rule
            self.reason = reason
        }
    }
}
