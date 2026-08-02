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
import File_System
import Linter
import Testing

@testable import Linter_Core

extension Lint.File.Single.Test {
    @Suite
    struct Eval {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

// MARK: - environment(inheriting:parent:)
//
// The eval dispatcher may add a parent-manifest channel, but it must preserve
// the coordinator's complete snapshot either way. In particular, SARIF must
// reach the compiled `Lint.run(configuration:)` terminal unchanged.

// MARK: - invalidateStaleResolution(evalRoot:)
//
// `.swift-lint/eval/` is reused across every dispatch for a consumer
// (`Lint.File.Single.State`). Every dependency the eval declares is
// `branch: "main"` — tag-free by design — but SwiftPM keeps an EXISTING
// `Package.resolved`'s pin for a branch-tracked dependency even when the
// branch has moved; it only re-resolves when no lockfile is present or on
// an explicit `swift package update`. Without invalidation, a consumer's
// eval project silently freezes at whatever engine commit was current the
// first time it was ever materialized — this was the root cause of
// swift-foundations/swift-linter#23 (`--format sarif` producing empty
// stdout against a package whose eval predated SARIF propagation).

extension Lint.File.Single.Test.Eval.Unit {
    private static func freshEvalRoot(key: Swift.String) -> File.Path {
        // swift-format-ignore: NeverUseForceTry
        try! File.Path.Temporary.deterministic(prefix: "lint-eval-invalidate-", key: key, suffix: "")
    }

    @Test
    func `A prior materialization's Package.resolved is removed before dispatch`() throws {
        let evalRoot: File.Path = Self.freshEvalRoot(key: "stale-lockfile")
        try File.Directory(evalRoot).create.recursive()
        let resolvedManifestPath: File.Path = evalRoot / "Package.resolved"
        try File(resolvedManifestPath).write.atomic(
            "{ \"pins\": [ \"stale-revision-predating-sarif-support\" ] }"
        )
        #expect(File(resolvedManifestPath).stat.exists)

        try Lint.File.Single.Eval.invalidateStaleResolution(evalRoot: evalRoot)

        #expect(!File(resolvedManifestPath).stat.exists)
    }

    @Test
    func `A prior materialization's cached workspace-state is also removed`() throws {
        // `Package.resolved` alone is NOT sufficient: SwiftPM's build system
        // separately caches the resolved dependency graph in
        // `.build/workspace-state.json` and restores `Package.resolved` FROM
        // that cache when only the lockfile is missing — confirmed against
        // the actual defect (swift-foundations/swift-linter#23), where
        // deleting only `Package.resolved` left the engine dependency
        // re-pinned to the exact same stale revision on the next dispatch.
        let evalRoot: File.Path = Self.freshEvalRoot(key: "stale-workspace-state")
        let buildDirectory: File.Path = evalRoot / ".build"
        try File.Directory(buildDirectory).create.recursive()
        let resolvedManifestPath: File.Path = evalRoot / "Package.resolved"
        let workspaceStatePath: File.Path = buildDirectory / "workspace-state.json"
        try File(resolvedManifestPath).write.atomic(
            "{ \"pins\": [ \"stale-revision-predating-sarif-support\" ] }"
        )
        try File(workspaceStatePath).write.atomic(
            "{ \"object\": { \"pins\": [ \"stale-revision-predating-sarif-support\" ] } }"
        )
        #expect(File(workspaceStatePath).stat.exists)

        try Lint.File.Single.Eval.invalidateStaleResolution(evalRoot: evalRoot)

        #expect(!File(resolvedManifestPath).stat.exists)
        #expect(!File(workspaceStatePath).stat.exists)
    }

    @Test
    func `Invalidation leaves the rest of the build cache untouched`() throws {
        // Only the two known resolution-state files go — compiled object
        // files and module caches survive, so an unchanged dependency graph
        // still benefits from SwiftPM's incremental build.
        let evalRoot: File.Path = Self.freshEvalRoot(key: "preserve-object-cache")
        let buildDirectory: File.Path = evalRoot / ".build"
        try File.Directory(buildDirectory).create.recursive()
        try File(evalRoot / "Package.resolved").write.atomic("{ }")
        try File(buildDirectory / "workspace-state.json").write.atomic("{ }")
        let unrelatedArtifact: File.Path = buildDirectory / "build.db"
        try File(unrelatedArtifact).write.atomic("unrelated compiled-artifact cache\n")

        try Lint.File.Single.Eval.invalidateStaleResolution(evalRoot: evalRoot)

        #expect(File(unrelatedArtifact).stat.exists)
    }
}

extension Lint.File.Single.Test.Eval.`Edge Case` {
    private static func freshEvalRoot(key: Swift.String) -> File.Path {
        // swift-format-ignore: NeverUseForceTry
        try! File.Path.Temporary.deterministic(prefix: "lint-eval-invalidate-edge-", key: key, suffix: "")
    }

    @Test
    func `First-ever materialization has no lockfile to remove, and is not an error`() throws {
        // Neither the eval root nor any of its ancestors exist yet — the exact
        // shape of a consumer's very first Shape-γ dispatch.
        let evalRoot: File.Path = Self.freshEvalRoot(key: "never-materialized")

        try Lint.File.Single.Eval.invalidateStaleResolution(evalRoot: evalRoot)
    }

    @Test
    func `Invalidation is idempotent across repeated calls`() throws {
        let evalRoot: File.Path = Self.freshEvalRoot(key: "idempotent")
        let buildDirectory: File.Path = evalRoot / ".build"
        try File.Directory(buildDirectory).create.recursive()
        let resolvedManifestPath: File.Path = evalRoot / "Package.resolved"
        let workspaceStatePath: File.Path = buildDirectory / "workspace-state.json"
        try File(resolvedManifestPath).write.atomic("{ }")
        try File(workspaceStatePath).write.atomic("{ }")

        try Lint.File.Single.Eval.invalidateStaleResolution(evalRoot: evalRoot)
        try Lint.File.Single.Eval.invalidateStaleResolution(evalRoot: evalRoot)

        #expect(!File(resolvedManifestPath).stat.exists)
        #expect(!File(workspaceStatePath).stat.exists)
    }
}

extension Lint.File.Single.Test.Eval.Unit {
    @Test
    func `SARIF selection survives eval without a parent manifest`() {
        let environment = Lint.File.Single.Eval.environment(
            inheriting: Environment.Snapshot([
                Lint.Reporter.Format.Channel.variable:
                    Lint.Reporter.Format.Channel.value(.sarif)
            ]),
            parent: nil
        )
        #expect(
            environment[Lint.Reporter.Format.Channel.variable]
                == Lint.Reporter.Format.Channel.value(.sarif)
        )
    }

    @Test
    func `Parent overlay preserves SARIF and adds only its channel`() {
        let parent = File.Path("/tmp/swift-linter-parent.json")
        let environment = Lint.File.Single.Eval.environment(
            inheriting: Environment.Snapshot([
                Lint.Reporter.Format.Channel.variable:
                    Lint.Reporter.Format.Channel.value(.sarif)
            ]),
            parent: parent
        )
        #expect(
            environment[Lint.Reporter.Format.Channel.variable]
                == Lint.Reporter.Format.Channel.value(.sarif)
        )
        #expect(environment[Lint.File.Single.Channel.parent.variable] == parent.string)
    }
}
