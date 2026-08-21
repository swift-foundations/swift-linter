public import Linter_Primitives

extension Lint.Run {

    public struct Outcome: Sendable, Equatable {

        public let findings: [Lint.Finding]

        public let suppressed: [Lint.Finding]

        public let filesLinted: Swift.Int

        @inlinable
        public init(
            findings: [Lint.Finding] = [],
            suppressed: [Lint.Finding] = [],
            filesLinted: Swift.Int = 0
        ) {
            self.findings = findings
            self.suppressed = suppressed
            self.filesLinted = filesLinted
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
