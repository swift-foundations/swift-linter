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

// The rules package is named by URL, not by a sibling-disk path. CI checks out
// the subject repository alone, so `../swift-institute-linter-rules` resolves
// only on a developer machine that happens to carry the sibling checkout — in
// the `Quality · swift-linter` job it is a hard "cannot be accessed" failure.
// The URL form is what the rest of the fleet declares.
Lint.run(dependencies: [
    .package(
        url: "https://github.com/swift-foundations/swift-institute-linter-rules.git",
        branch: "main",
        products: ["Linter Institute Rules"]
    ),
]) {
    Lint.Rule.Bundle.institute
}
