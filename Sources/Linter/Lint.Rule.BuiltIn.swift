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

/// The catalog of built-in rules shipped with swift-linter.
///
/// This is the single registration point for built-in rules. Adding a new
/// rule is a one-line edit here plus the rule's own implementation file.
/// The CLI consumes this catalog without code changes; consumers who embed
/// the library can extend or replace it.
///
/// **Phase 1 catalog**: R5 (`Lint.Rule.Unchecked` — `__unchecked:` at
/// call sites only).
///
/// **Phase 2 Stream A additions** (per
/// `swift-institute/Research/swiftsyntax-based-custom-linter-investigation.md`):
/// R1 (`Lint.Rule.Cardinal.Count` — `count - 1` and algebraic-flip
/// equivalents), R2 (`Lint.Rule.Cardinal.Constructor` — `Cardinal(0)`
/// / `Cardinal(1)`), R3 (`Lint.Rule.RawValue.Chain` — chained
/// `.rawValue.X` member access), R4 (`Lint.Rule.RawValue.BitPattern`
/// — `X(bitPattern: …rawValue)` integration-overload anti-pattern).
///
/// **Phase 2+ remaining**: R0 positive enforcement of [CONV-016],
/// `[API-IMPL-005]` per-path scoping, `[TEST-025]` file-context,
/// complex multi-decl rules from
/// `mechanical-rule-tool-classification-swift-primitives.md`.
extension Lint.Rule {
    public static let builtIn: [any Lint.Rule.`Protocol`] = [
        Lint.Rule.Unchecked(),
        Lint.Rule.Cardinal.Count(),
        Lint.Rule.Cardinal.Constructor(),
    ]
}
