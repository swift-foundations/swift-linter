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

public import Cardinal_Primitives
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
    /// The four counts are typed `Tagged<Domain, Cardinal>` (a *cardinal of
    /// rules / source files / findings*) per `[IMPL-010]`. They spell the same
    /// underlying types as Linter Core's `Lint.Rule.Count` / `Lint.Source.Count`
    /// / `Lint.Finding.Count` aliases; Reporter Text cannot import Linter Core
    /// (sibling targets), so the `Tagged<…>` form is written out. `Cardinal`'s
    /// `CustomStringConvertible` (Cardinal Primitives SLI) forwards through
    /// `Tagged`, so the counts interpolate to their decimal `rawValue` directly.
    public static func line(
        package: Swift.String,
        activeRules: Tagged<Lint.Rule, Cardinal>,
        excludedRules: Tagged<Lint.Rule, Cardinal>,
        filesLinted: Tagged<Lint.Source, Cardinal>,
        violations: Tagged<Lint.Finding, Cardinal>
    ) -> Swift.String {
        let ruleSet: Swift.String = excludedRules > .zero
            ? "\(activeRules) active rules (−\(excludedRules) excluded)"
            : "\(activeRules) active rules"
        let fileWord: Swift.String = filesLinted == .one ? "file" : "files"
        let violationWord: Swift.String = violations == .one ? "violation" : "violations"
        return "\(package) · \(ruleSet) · \(filesLinted) \(fileWord) linted · \(violations) \(violationWord)"
    }
}
