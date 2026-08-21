extension Lint.Run {

    public struct Summary: Sendable, Equatable {

        public let files: Swift.Int

        public let activeRules: Swift.Int

        public let applicableRules: Swift.Int

        public let applicableObservations: Swift.Int

        public let measuredObservations: Swift.Int

        public let unmeasuredObservations: Swift.Int

        public let findings: Swift.Int

        public let suppressed: Swift.Int

        public let repairProposals: Swift.Int

        @inlinable
        public init(
            files: Swift.Int,
            activeRules: Swift.Int,
            applicableRules: Swift.Int,
            applicableObservations: Swift.Int,
            measuredObservations: Swift.Int,
            unmeasuredObservations: Swift.Int,
            findings: Swift.Int,
            suppressed: Swift.Int,
            repairProposals: Swift.Int
        ) {
            self.files = files
            self.activeRules = activeRules
            self.applicableRules = applicableRules
            self.applicableObservations = applicableObservations
            self.measuredObservations = measuredObservations
            self.unmeasuredObservations = unmeasuredObservations
            self.findings = findings
            self.suppressed = suppressed
            self.repairProposals = repairProposals
        }
    }
}
