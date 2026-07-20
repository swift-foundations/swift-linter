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

extension Lint.File.Single.Test.Runner {
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

// MARK: - route(output:classification:)
//
// Hole 1c gate. The prebuilt runner bakes a single output shape (text format,
// advisory exit). It cannot reshape output for `--format sarif` or escalate
// for `--exit-policy strict`, so a non-standard output request MUST route to
// the eval fallback regardless of the source classification — the runner must
// never be entered for output it cannot produce. `.standard` output defers
// entirely to the source classification.

extension Lint.File.Single.Test.Runner {
    private func isEvalFallback(_ classification: Lint.File.Single.Classification) -> Swift.Bool {
        if case .evalFallback = classification { return true }
        return false
    }

    @Test
    func `Standard output preserves a bare-bundle fast-path classification`() {
        #expect(
            Lint.File.Single.route(output: .standard, classification: .fastPathStandardBundle(bundle: .primitives))
                == .fastPathStandardBundle(bundle: .primitives)
        )
    }

    @Test
    func `Standard output preserves an excluding fast-path classification`() {
        let excluding: Lint.File.Single.Classification =
            .fastPathStandardBundleExcluding(bundle: .primitives, disabled: ["raw value access"])
        #expect(Lint.File.Single.route(output: .standard, classification: excluding) == excluding)
    }

    @Test
    func `Standard output preserves an eval-fallback classification`() {
        #expect(
            isEvalFallback(
                Lint.File.Single.route(
                    output: .standard,
                    classification: .evalFallback(reason: "inline rule")
                )
            )
        )
    }

    @Test
    func `Non-standard output forces eval even for a bare-bundle fast path`() {
        // `--format sarif` / `--exit-policy strict` ⇒ the runner can't produce
        // the requested shape, so route to eval despite a fast-path source.
        #expect(
            isEvalFallback(
                Lint.File.Single.route(output: .nonStandard, classification: .fastPathStandardBundle(bundle: .primitives))
            )
        )
    }

    @Test
    func `Non-standard output forces eval even for an excluding fast path`() {
        #expect(
            isEvalFallback(
                Lint.File.Single.route(
                    output: .nonStandard,
                    classification: .fastPathStandardBundleExcluding(bundle: .primitives, disabled: ["int public parameter"])
                )
            )
        )
    }
}
