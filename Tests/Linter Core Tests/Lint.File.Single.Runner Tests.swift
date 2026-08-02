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

import Environment
import Linter
import Testing

@testable import Linter_Core

extension Lint.File.Single.Test {
    @Suite
    struct Runner {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

// MARK: - Lint.File.Single.Runner.invocation(binary:arguments:)
//
// Hole 1a regression. The prebuilt-runner fast path MUST forward the
// consumer's CLI `arguments` (the lint-target paths) so it lints EXACTLY the
// paths the eval path lints — `Manifest.Executable.dispatch` appends the same
// vector to its `swift run … Lint` invocation. The prior invocation
// `[binary, consumerPackageRoot.string]` dropped `arguments`, so a multi-path
// or non-cwd target was silently linted as just the package root: a
// wrong-result-that-exits-0 fast-path/eval divergence. These tests pin that
// the invocation forwards `arguments` verbatim.

extension Lint.File.Single.Test.Runner.Unit {
    @Test
    func `Multi-path arguments are forwarded verbatim after the binary`() {
        let invocation = Lint.File.Single.Runner.invocation(
            binary: "/usr/local/bin/swift-linter-runner",
            arguments: ["Sources", "Tests"]
        )
        #expect(invocation == ["/usr/local/bin/swift-linter-runner", "Sources", "Tests"])
    }

    @Test
    func `A single dot target is forwarded`() {
        let invocation = Lint.File.Single.Runner.invocation(
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
        let invocation = Lint.File.Single.Runner.invocation(
            binary: "runner",
            arguments: []
        )
        #expect(invocation == ["runner"])
    }
}

// MARK: - environment(inheriting:bundle:selection:)
//
// The runner boundary owns only its bundle and selection overlays. It must
// preserve the coordinator's complete environment so the shared
// `Lint.run(configuration:)` terminal receives the exact requested report
// format instead of silently reverting to text.

extension Lint.File.Single.Test.Runner.Unit {
    @Test
    func `SARIF selection survives the prebuilt runner environment boundary`() {
        let environment = Lint.File.Single.Runner.environment(
            inheriting: Environment.Snapshot([
                Lint.Reporter.Format.Channel.variable:
                    Lint.Reporter.Format.Channel.value(.sarif)
            ]),
            bundle: .primitives,
            selection: nil
        )
        #expect(
            environment[Lint.Reporter.Format.Channel.variable]
                == Lint.Reporter.Format.Channel.value(.sarif)
        )
    }

    @Test
    func `Runner overlays do not replace an explicitly selected text format`() {
        let environment = Lint.File.Single.Runner.environment(
            inheriting: Environment.Snapshot([
                Lint.Reporter.Format.Channel.variable:
                    Lint.Reporter.Format.Channel.value(.text)
            ]),
            bundle: .standards,
            selection: nil
        )
        #expect(
            environment[Lint.Reporter.Format.Channel.variable]
                == Lint.Reporter.Format.Channel.value(.text)
        )
    }

    @Test
    func `Runner adds its bundle without dropping unrelated channels`() {
        let environment = Lint.File.Single.Runner.environment(
            inheriting: Environment.Snapshot(["SWIFT_LINTER_TEST_SENTINEL": "preserved"]),
            bundle: .institute,
            selection: nil
        )
        #expect(environment["SWIFT_LINTER_TEST_SENTINEL"] == "preserved")
        #expect(
            environment[Lint.Rule.Bundle.Baked.Channel.variable]
                == Lint.Rule.Bundle.Baked.institute.rawValue
        )
    }
}
