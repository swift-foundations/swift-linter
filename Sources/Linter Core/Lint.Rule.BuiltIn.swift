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
public import Linter_Rule_Unchecked
public import Linter_Rule_Cardinal
public import Linter_Rule_RawValue
public import Linter_Rule_ResultBuilder

// Wave 1 — AI-harness rules (Phase 4).
public import Linter_Rule_Try_Optional
public import Linter_Rule_Untyped_Throws
public import Linter_Rule_Existential_Throws
public import Linter_Rule_Var_Named_Impl
public import Linter_Rule_Option_Named_Flags
public import Linter_Rule_Compound_Identifier
public import Linter_Rule_Tag_Suffix

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
/// **Phase 4 Wave 1 additions** (per
/// `HANDOFF-swift-linter-rules-wave-1-encoding.md`): try_optional,
/// untyped_throws, existential_throws, var_named_impl,
/// option_named_flags, compound_identifier, tag_suffix. Each rule
/// cites a skill ID or feedback-memory in its diagnostic message.
/// Registration in `builtIn` makes these rules available via the
/// metatype-based Lint.swift DSL; activation per consumer remains
/// opt-in via the consumer's Lint.swift `enabledRuleIDs` list (Tier
/// 1/Tier 2 canonical Lint.swift files do NOT auto-enable wave-1
/// rules per the brief's MUST NOT #4).
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
        Lint.Rule.RawValue.Chain(),
        Lint.Rule.RawValue.BitPattern(),
        Lint.Rule.ResultBuilderForLoop(),
        Lint.Rule.TryOptional(),
        Lint.Rule.UntypedThrows(),
        Lint.Rule.ExistentialThrows(),
        Lint.Rule.VarNamedImpl(),
        Lint.Rule.OptionNamedFlags(),
        Lint.Rule.CompoundIdentifier(),
        Lint.Rule.TagSuffix(),
    ]
}
