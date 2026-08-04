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

import Linter

// Degenerate-catalogue fixture: a VALID token (`primitives`) present in the
// runner's bake catalogue but resolving to ZERO configured rules. This is
// the exact shape of the fail-open §3 item 9 describes — "an unset linter
// channel can load the wrong/no rules and return zero findings" — reachable
// even after the channel itself is read correctly, if the resolved bundle
// is empty. `Lint.run(bundles:)` must refuse to report this as a clean run.
Lint.run(bundles: [
    .primitives: []
])
