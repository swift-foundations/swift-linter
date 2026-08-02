// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-linter open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-linter project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import Terminal_Primitives

extension Lint.Reporter.Format {
    /// Emit findings in this format via the supplied write surface.
    ///
    /// This is the single format-to-reporter selection point used by both the
    /// CLI's in-process path and configured `Lint.run(configuration:)`
    /// executables. Concrete serialization remains owned by the existing Text
    /// and SARIF reporters.
    public func emit(
        findings: [Lint.Finding],
        to write: Terminal.Stream.Write
    ) {
        switch self {
        case .text:
            Lint.Reporter.Text.emit(findings: findings, to: write)

        case .sarif:
            Lint.Reporter.SARIF.emit(findings: findings, to: write)
        }
    }

    /// Build a complete report in this format.
    ///
    /// The pure counterpart to ``emit(findings:to:)`` keeps format-boundary
    /// tests independent of process stdout while reusing each reporter's
    /// canonical content.
    public func report(for findings: [Lint.Finding]) -> Swift.String {
        switch self {
        case .text:
            Lint.Reporter.Text.report(for: findings)

        case .sarif:
            Lint.Reporter.SARIF.report(for: findings)
        }
    }
}
