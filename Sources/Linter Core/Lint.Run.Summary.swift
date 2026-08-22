extension Lint.Run {

    public struct Summary: Sendable, Equatable {

        public let files: Swift.Int

        public let rules: Swift.Int

        public let applicable: Swift.Int

        public let observations: Swift.Int

        public let measured: Swift.Int

        public let unmeasured: Swift.Int

        public let findings: Swift.Int

        public let suppressed: Swift.Int

        public let repairs: Swift.Int

        @inlinable
        public init(
            files: Swift.Int,
            rules: Swift.Int,
            applicable: Swift.Int,
            observations: Swift.Int,
            measured: Swift.Int,
            unmeasured: Swift.Int,
            findings: Swift.Int,
            suppressed: Swift.Int,
            repairs: Swift.Int
        ) {
            self.files = files
            self.rules = rules
            self.applicable = applicable
            self.observations = observations
            self.measured = measured
            self.unmeasured = unmeasured
            self.findings = findings
            self.suppressed = suppressed
            self.repairs = repairs
        }
    }
}
