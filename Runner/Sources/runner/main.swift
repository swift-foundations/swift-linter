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

// Phase-3 standard runner body. The engine + SwiftSyntax + the standard
// primitives rule packs are baked into this executable; `Lint.run(bundle:)`
// reads the target directory from argv and lints it warm — no per-run eval
// recompile. It bakes the BARE standard `Lint.Rule.Bundle.primitives` (the
// canonical pure-bundle selection the swift-linter CLI fast path routes here),
// so a bare-bundle consumer gets exactly the rule set its eval would resolve.
// Per-consumer excludes/enables are NOT baked — they are a runtime-selection
// concern and such consumers take the eval fallback today (see the research
// doc's Phase-3 §, "runtime-selection overlay").
import Linter
import Linter_Primitives_Rules

Lint.run(bundle: Lint.Rule.Bundle.primitives)
