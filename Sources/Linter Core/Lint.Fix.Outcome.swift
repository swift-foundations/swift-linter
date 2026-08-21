public import File_System

extension Lint.Fix {

    public struct Outcome: Sendable, Equatable {

        public let changes: [Change]

        public let excludedRules: [Lint.Rule.ID]

        public let plannedRules: [Lint.Rule.ID]

        public let published: [File.Path]

        public let refusals: [Refusal]

        public let filesScanned: Swift.Int

        public let fixableRules: Swift.Int

        @inlinable
        public init(
            changes: [Change] = [],
            excludedRules: [Lint.Rule.ID] = [],
            plannedRules: [Lint.Rule.ID] = [],
            published: [File.Path] = [],
            refusals: [Refusal] = [],
            filesScanned: Swift.Int = 0,
            fixableRules: Swift.Int = 0
        ) {
            self.changes = changes
            self.excludedRules = excludedRules
            self.plannedRules = plannedRules
            self.published = published
            self.refusals = refusals
            self.filesScanned = filesScanned
            self.fixableRules = fixableRules
        }
    }
}
