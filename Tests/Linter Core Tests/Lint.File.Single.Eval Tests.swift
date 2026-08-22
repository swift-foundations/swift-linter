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

extension Lint.File.Single.Test.Eval.Unit {
    private static func freshEvalRoot(key: Swift.String) -> File.Path {

        try! File.Path.Temporary.deterministic(
            prefix: "lint-eval-invalidate-",
            key: key,
            suffix: ""
        )
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

        try Lint.File.Single.Eval.invalidate(resolutionAt: evalRoot)

        #expect(!File(resolvedManifestPath).stat.exists)
    }

    @Test
    func `A prior materialization's cached workspace-state is also removed`() throws {

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

        try Lint.File.Single.Eval.invalidate(resolutionAt: evalRoot)

        #expect(!File(resolvedManifestPath).stat.exists)
        #expect(!File(workspaceStatePath).stat.exists)
    }

    @Test
    func `Invalidation leaves the rest of the build cache untouched`() throws {

        let evalRoot: File.Path = Self.freshEvalRoot(key: "preserve-object-cache")
        let buildDirectory: File.Path = evalRoot / ".build"
        try File.Directory(buildDirectory).create.recursive()
        try File(evalRoot / "Package.resolved").write.atomic("{ }")
        try File(buildDirectory / "workspace-state.json").write.atomic("{ }")
        let unrelatedArtifact: File.Path = buildDirectory / "build.db"
        try File(unrelatedArtifact).write.atomic("unrelated compiled-artifact cache\n")

        try Lint.File.Single.Eval.invalidate(resolutionAt: evalRoot)

        #expect(File(unrelatedArtifact).stat.exists)
    }
}

extension Lint.File.Single.Test.Eval.`Edge Case` {
    private static func freshEvalRoot(key: Swift.String) -> File.Path {

        try! File.Path.Temporary.deterministic(
            prefix: "lint-eval-invalidate-edge-",
            key: key,
            suffix: ""
        )
    }

    @Test
    func `First-ever materialization has no lockfile to remove, and is not an error`() throws {

        let evalRoot: File.Path = Self.freshEvalRoot(key: "never-materialized")

        try Lint.File.Single.Eval.invalidate(resolutionAt: evalRoot)
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

        try Lint.File.Single.Eval.invalidate(resolutionAt: evalRoot)
        try Lint.File.Single.Eval.invalidate(resolutionAt: evalRoot)

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
