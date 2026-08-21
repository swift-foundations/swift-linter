public import File_System
public import Linter_Primitives

extension Lint.Run {

    public struct Outcome: Sendable, Equatable {

        public let findings: [Lint.Finding]

        public let suppressed: [Lint.Finding]

        public let files: [File.Path]

        public let activeRules: [Lint.Rule.ID]

        public let observations: [Observation]

        public let repairProposals: [Repair.Proposal]

        @inlinable
        public init(
            findings: [Lint.Finding] = [],
            suppressed: [Lint.Finding] = [],
            files: [File.Path] = [],
            activeRules: [Lint.Rule.ID] = [],
            observations: [Observation] = [],
            repairProposals: [Repair.Proposal] = []
        ) {
            self.findings = findings
            self.suppressed = suppressed
            self.files = files
            self.activeRules = activeRules
            self.observations = observations
            self.repairProposals = repairProposals
        }

        @inlinable
        public var filesLinted: Swift.Int { files.count }

        @inlinable
        public var applicableRules: [Lint.Rule.ID] {
            activeRules.filter { rule in
                observations.contains { $0.rule == rule && $0.applicable }
            }
        }

        @inlinable
        public var summary: Summary {
            Summary(
                files: files.count,
                activeRules: activeRules.count,
                applicableRules: applicableRules.count,
                applicableObservations: observations.count { $0.applicable },
                measuredObservations: observations.count {
                    $0.coverage == .measured
                },
                unmeasuredObservations: observations.count {
                    if case .unmeasured = $0.coverage { true } else { false }
                },
                findings: findings.count,
                suppressed: suppressed.count,
                repairProposals: repairProposals.count
            )
        }
    }
}

extension Lint.Run.Outcome {

    public var violations: [Lint.Finding] {
        findings.filter { finding in
            switch finding.record.severity {
            case .error, .warning: true
            case .note, .remark: false
            }
        }
    }
}
