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

import Testing
@testable import Linter_Core

extension Lint.File.Single.Test {
    @Suite
    struct Runner {}
}

// MARK: - runnerInvocation(binary:arguments:)
//
// Hole 1a regression. The prebuilt-runner fast path MUST forward the
// consumer's CLI `arguments` (the lint-target paths) so it lints EXACTLY the
// paths the eval path lints — `Manifest.Executable.dispatch` appends the same
// vector to its `swift run … Lint` invocation. The prior invocation
// `[binary, consumerPackageRoot.string]` dropped `arguments`, so a multi-path
// or non-cwd target was silently linted as just the package root: a
// wrong-result-that-exits-0 fast-path/eval divergence. These tests pin that
// the invocation forwards `arguments` verbatim.

extension Lint.File.Single.Test.Runner {
    @Test
    func `Multi-path arguments are forwarded verbatim after the binary`() {
        let invocation = Lint.File.Single.runnerInvocation(
            binary: "/usr/local/bin/swift-linter-runner",
            arguments: ["Sources", "Tests"]
        )
        #expect(invocation == ["/usr/local/bin/swift-linter-runner", "Sources", "Tests"])
    }

    @Test
    func `A single dot target is forwarded`() {
        let invocation = Lint.File.Single.runnerInvocation(
            binary: "runner",
            arguments: ["."]
        )
        #expect(invocation == ["runner", "."])
    }

    @Test
    func `Empty arguments yield just the binary (Lint.run applies its dot default)`() {
        // An empty argument vector mirrors the eval path: `swift run … Lint`
        // with no trailing args, where `Lint.run(configuration:)` falls back
        // to `["."]`. The fast path must match — no synthetic consumer-root
        // argument that the eval path never receives.
        let invocation = Lint.File.Single.runnerInvocation(
            binary: "runner",
            arguments: []
        )
        #expect(invocation == ["runner"])
    }
}
