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

public import Linter_Primitives

extension Lint.Reporter.Text {
    /// The always-on run-summary line emitted to stderr by
    /// ``emit(summaryFor:activeRules:excludedRules:filesLinted:violations:to:)``.
    ///
    /// A nested accessor per `[API-NAME-002]` — `Lint.Reporter.Text.Summary.line(…)`
    /// rather than a compound `summaryLine`.
    public enum Summary {}
}

extension Lint.Reporter.Text.Summary {
    /// Pure formatter for the run-summary line (no trailing newline). Split
    /// out so the field composition is unit-testable without a write surface.
    ///
    /// Shape: `<package> · <K> active rules[ (−<M> excluded)] · <F> files linted · <V> violations`.
    /// `K` is the *effective* active-rule count (after bundle composition AND
    /// any runtime overlay/exclusions), so it reflects what actually ran; `M`
    /// (the runtime-disabled count) annotates the overlay/exclusion case.
    ///
    /// The four counts are bare `Int`: display-only cardinalities formatted
    /// into this one line, never indexed or arithmetic-combined. Typing them
    /// (`Count`/`Index<Element>.Count`) would pull a cardinal/collection
    /// dependency tree into the reporter for no semantic gain — leanness wins
    /// for display values (the `int public parameter` finding here is a known,
    /// accepted advisory).
    public static func line(
        package: Swift.String,
        activeRules: Swift.Int,
        excludedRules: Swift.Int,
        filesLinted: Swift.Int,
        violations: Swift.Int
    ) -> Swift.String {
        let ruleSet: Swift.String = excludedRules > 0
            ? "\(activeRules) active rules (−\(excludedRules) excluded)"
            : "\(activeRules) active rules"
        let fileWord: Swift.String = filesLinted == 1 ? "file" : "files"
        let violationWord: Swift.String = violations == 1 ? "violation" : "violations"
        return "\(package) · \(ruleSet) · \(filesLinted) \(fileWord) linted · \(violations) \(violationWord)"
    }
}
