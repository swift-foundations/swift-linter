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

// Phase-3 standard runner body. The engine + SwiftSyntax + EVERY published
// standard rule-pack bundle are baked into this executable;
// `Lint.run(bundles:)` reads the dispatcher-exported SWIFT_LINTER_BUNDLE
// channel to select WHICH baked bundle this spawn lints with, then reads the
// target directory from argv and lints it warm — no per-run eval recompile.
// The swift-linter CLI fast path routes a pure-bundle consumer here only when
// its active rule set is provably exactly one of these bundles (or a bundle
// minus exactly-extracted exclusions), so the runner never lints a different
// rule set than the consumer selected (A4-gap closure). An unset channel
// defaults to `.primitives` — the sole bundle a pre-A4 dispatcher ever
// routed. A token this catalogue does not carry fails loud (dispatcher/runner
// version skew). Per-consumer excludes are NOT baked — they ride the
// selection-manifest channel as a runtime overlay, exactly as before.
import Linter
import Linter_Institute_Rules
import Linter_Primitives_Rules
import Linter_Standards_Rules

Lint.run(bundles: [
    .primitives: Lint.Rule.Bundle.primitives,
    .standards: Lint.Rule.Bundle.standards,
    .institute: Lint.Rule.Bundle.institute,
])
