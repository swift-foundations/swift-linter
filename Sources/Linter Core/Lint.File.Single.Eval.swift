internal import Environment
internal import File_System
internal import Manifest_Executable
internal import Manifest_Primitives
internal import Manifest_Resolver
internal import Package_Primitives
internal import SPM_Standard
internal import SwiftSyntax
internal import URI_Standard_Library_Integration

extension Lint.File.Single {

    public enum Eval: Swift.Sendable {}
}

extension Lint.File.Single.Eval {

    private static let engineDependencyURL: URI =
        "https://github.com/swift-foundations/swift-linter.git"

    private static let engineDependencyBranch: Swift.String = "main"

    internal static func run(
        consumerPackageRoot: File.Path,
        consumerLintSwiftPath: File.Path,
        source: Swift.String,
        parsed: SourceFileSyntax,
        arguments: [Swift.String],
        nonce: Swift.String
    ) throws(Lint.File.Single.Error) -> Swift.Int32 {

        let extractedDependencies: [Package.Dependency] = try Lint.File.Single.Extractor
            .dependencies(
                parsed: parsed,
                sourcePath: consumerLintSwiftPath,
                consumerPackageRoot: consumerPackageRoot
            )

        let parentManifestPath: File.Path? = try Self.resolveParentChain(
            consumerSource: source,
            consumerPackageRoot: consumerPackageRoot,
            nonce: nonce
        )

        let linterDependency: Package.Dependency
        if let rawPath: Swift.String = Environment.read("SWIFT_LINTER_PATH") {
            do throws(Paths.Path.Error) {
                _ = try Paths.Path(rawPath)
            } catch {
                throw .materializationFailed(
                    reason: "SWIFT_LINTER_PATH `\(rawPath)` is not a valid path: \(error)"
                )
            }
            linterDependency = Package.Dependency(
                source: .path(rawPath),
                name: "swift-linter",
                products: ["Linter"]
            )
        } else {
            linterDependency = Self.publishedEngineDependency()
        }
        let dependencies: [Package.Dependency] = [linterDependency] + extractedDependencies

        let environment: [Swift.String: Swift.String] = Self.environment(
            inheriting: Environment.Snapshot.current(),
            parent: parentManifestPath
        )

        let stateRoot: File.Path
        do throws(Lint.File.Single.State.Error) {
            stateRoot = try Lint.File.Single.State.create(consumerPackageRoot: consumerPackageRoot)
        } catch {
            throw .materializationFailed(reason: "create state directory: \(error)")
        }
        let evalRoot: File.Path = stateRoot / "eval"

        try Self.invalidate(resolutionAt: evalRoot)
        let configuration = Manifest.Executable.Configuration(
            consumerPackageRoot: consumerPackageRoot,
            consumerSourcePath: consumerLintSwiftPath,
            evalRoot: evalRoot,
            executableName: "Lint",
            dependencies: dependencies,
            platforms: [".macOS(.v27)"],
            swiftLanguageModes: [".v6"],
            ecosystemSettings: [
                ".enableUpcomingFeature(\"ExistentialAny\")",
                ".enableUpcomingFeature(\"InternalImportsByDefault\")",
                ".enableUpcomingFeature(\"MemberImportVisibility\")",
                ".enableUpcomingFeature(\"NonisolatedNonsendingByDefault\")",
            ],
            arguments: arguments,
            environment: environment,
            toolsVersion: "6.3.1"
        )

        do throws(Manifest.Executable.Error) {
            return try Manifest.Executable.dispatch(configuration: configuration)
        } catch {
            switch error {
            case .readFailed(let path, let description):
                throw .readFailed(path: path, description: description)

            case .materializationFailed(let reason):
                throw .materializationFailed(reason: reason)

            case .spawnFailed(let consumerPackageRoot, let description):
                throw .spawnFailed(
                    consumerPackageRoot: consumerPackageRoot,
                    description: description
                )
            }
        }
    }

    internal static func invalidate(
        resolutionAt evalRoot: File.Path
    ) throws(Lint.File.Single.Error) {
        let staleStatePaths: [File.Path] = [
            evalRoot / "Package.resolved",
            evalRoot / ".build" / "workspace-state.json",
        ]
        for path in staleStatePaths {
            do throws(File.System.Delete.Error) {
                try File(path).delete.ifExists()
            } catch {
                throw .materializationFailed(
                    reason: "invalidate stale eval resolution at \(path): \(error)"
                )
            }
        }
    }

    internal static func environment(
        inheriting snapshot: Environment.Snapshot,
        parent manifest: File.Path?
    ) -> [Swift.String: Swift.String] {
        var environment = snapshot
        if let manifest {
            environment.values[Lint.File.Single.Channel.parent.variable] = manifest.string
        }
        return environment.values
    }

    private static func publishedEngineDependency() -> Package.Dependency {
        let branch: Swift.String =
            Environment.read("SWIFT_LINTER_BRANCH") ?? Self.engineDependencyBranch
        return Package.Dependency(
            source: .url(Self.engineDependencyURL, branch: branch),
            name: "swift-linter",
            products: ["Linter"]
        )
    }

    private static func resolveParentChain(
        consumerSource: Swift.String,
        consumerPackageRoot: File.Path,
        nonce: Swift.String
    ) throws(Lint.File.Single.Error) -> File.Path? {
        guard let linterPath: Swift.String = Environment.read("SWIFT_LINTER_PATH") else {
            return nil
        }
        let linter: File.Path
        do throws(Paths.Path.Error) {
            linter = try File.Path(linterPath)
        } catch {
            return nil
        }
        guard let workspace: File.Path = linter.parent else {
            return nil
        }
        let parentDependencies: [Manifest.Dependency] = [
            Manifest.Dependency(
                path: (workspace / "swift-json").string,
                name: "swift-json",
                product: "JSON",
                imports: ["JSON"]
            ),
            Manifest.Dependency(
                path: (workspace / "swift-file-system").string,
                name: "swift-file-system",
                product: "File System",
                imports: ["File_System"]
            ),
            Manifest.Dependency(
                path: linterPath,
                name: "swift-linter",
                product: "Linter",
                imports: ["Linter"]
            ),
        ]
        let parentChain: [Lint.Manifest]
        do throws(Manifest.Resolver<Lint.Manifest, Lint.Manifest>.Error) {
            parentChain = try Manifest.Resolver<Lint.Manifest, Lint.Manifest>.walkParents(
                from: consumerSource,
                filename: "Lint.swift",
                dependencies: parentDependencies
            )
        } catch {

            return nil
        }
        guard !parentChain.isEmpty else {
            return nil
        }
        let folded: Lint.Manifest = Self.foldParents(parentChain)
        do throws(Lint.File.Single.Channel.Error) {
            return try Lint.File.Single.Channel.parent.write(
                folded,
                consumerPackageRoot: consumerPackageRoot,
                nonce: nonce
            )
        } catch {
            throw .materializationFailed(reason: "write parent manifest: \(error)")
        }
    }

    private static func foldParents(_ chain: [Lint.Manifest]) -> Lint.Manifest {
        var enabled: Set<Lint.Rule.ID> = []
        var disabled: Set<Lint.Rule.ID> = []
        var excluded: [File.Path] = []
        for parent in chain {
            enabled.formUnion(parent.rules.enabled)
            disabled.formUnion(parent.rules.disabled)
            excluded.append(contentsOf: parent.excluded)
        }
        return Lint.Manifest(
            enabled: enabled,
            disabled: disabled,
            excluded: excluded
        )
    }
}
