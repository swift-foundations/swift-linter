// swift-linter-tools-version: 0.1
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

// Foundation-up dogfeed. swift-linter is the L3 foundations-tier engine +
// CLI + Materializer + Dispatch + Reporter. It is not a primitives-tier
// package, so it loads `Lint.Rule.Bundle.institute` (universal + institute
// tier) rather than the primitives bundle — primitives-tier rules
// (Tagged/Cardinal/RawValue chains) don't apply outside the L1 layer.

import Linter
import Linter_Institute_Rules

Lint.run(dependencies: [
    Package.Dependency(
        source: .path("../swift-institute-linter-rules"),
        name: "swift-institute-linter-rules",
        products: ["Linter Institute Rules"]
    ),
]) {
    Lint.Rule.Bundle.institute
}
