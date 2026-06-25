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

// MARK: - Run-summary count vocabulary
//
// `Count = Tagged<Domain, Cardinal>` (a *cardinal of what*), per-domain
// typealias homed WITH the domain type — `Text.Count = Tagged<Text, Cardinal>`
// (text-primitives), `Kernel.Thread.Count = Tagged<…, Cardinal>` (kernel).
// There is NO bare generic `Count<T>`; bare `Cardinal` is discouraged ("a
// Cardinal of WHAT"). These three counts carry the run-summary fields so the
// public reporter/outcome surface reads typed intent rather than a raw
// machine integer (`[IMPL-010]`).
//
// TODO: the institute-correct home for these typealiases is
// swift-linter-primitives (where `Lint.Rule` / `Lint.Source` / `Lint.Finding`
// live). They are defined LOCALLY here for now so the type-strengthening lands
// without a cross-package edit; promote them to swift-linter-primitives once
// the principal ratifies the cross-package leg.

extension Lint.Rule {
    /// A cardinal count of lint rules — the run-summary's *active* and
    /// *excluded* rule fields. `Tagged<Lint.Rule, Cardinal>`.
    public typealias Count = Tagged<Lint.Rule, Cardinal>
}

extension Lint.Source {
    /// A cardinal count of source files — the run-summary's *files linted*
    /// field. `Tagged<Lint.Source, Cardinal>`.
    public typealias Count = Tagged<Lint.Source, Cardinal>
}

extension Lint.Finding {
    /// A cardinal count of findings — the run-summary's *violations* field.
    /// `Tagged<Lint.Finding, Cardinal>`.
    public typealias Count = Tagged<Lint.Finding, Cardinal>
}
