internal import Environment
public import File_System
internal import Linter_Primitives
internal import Manifest_Loader
internal import Manifest_Primitives
internal import Manifest_Resolver

extension Lint {

    public enum Driver {}
}

extension Lint.Driver {

    @inlinable
    public static var dispatch: Dispatch.Type { Dispatch.self }

    @inlinable
    public static var manifest: Manifest.Type { Manifest.self }
}

extension Lint.Driver {

    public static func configuration(
        at consumerPackageRoot: File.Path,
        manifestOverride: File.Path? = nil,
        onMissingLinterPath: () -> Void = {}
    ) -> Lint.Configuration {
        let manifestDirectory: Swift.String
        let manifestFilename: Swift.String
        if let override = manifestOverride {
            manifestDirectory = override.parent.map { $0.description } ?? "."
            manifestFilename = override.components.last.map { $0.string } ?? "Lint.swift"
        } else {
            guard Self.manifest.path(at: consumerPackageRoot) != nil else {
                return defaultConfiguration()
            }
            manifestDirectory = consumerPackageRoot.string
            manifestFilename = "Lint.swift"
        }

        guard let dependencies = manifestDependencies() else {
            onMissingLinterPath()
            return defaultConfiguration()
        }
        do throws(Manifest_Resolver.Manifest.Resolver<Lint.Manifest, Lint.Configuration>.Error) {
            return try Manifest_Resolver.Manifest.Resolver<Lint.Manifest, Lint.Configuration>
                .resolve(
                    consumerPackageRoot: manifestDirectory,
                    filename: manifestFilename,
                    dependencies: dependencies,
                    defaultConfiguration: defaultConfiguration,
                    buildConfiguration: { manifest, parent in
                        configuration(from: manifest, parent: parent)
                    }
                )
        } catch {

            return defaultConfiguration()
        }
    }
}

extension Lint.Driver {

    fileprivate static func defaultConfiguration() -> Lint.Configuration {
        Lint.Configuration {}
    }

    internal static func configuration(
        from manifest: Lint.Manifest,
        parent: Lint.Configuration?
    ) -> Lint.Configuration {
        Lint.Configuration(
            inheriting: parent,
            excluded: manifest.excluded.map(Lint.Filter.Prefix.init),
            disabled: manifest.rules.disabled
        ) {}
    }

    fileprivate static func manifestDependencies() -> [Manifest_Primitives.Manifest.Dependency]? {

        guard let linterPath = Environment.read("SWIFT_LINTER_PATH") else {
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
        return [
            Manifest_Primitives.Manifest.Dependency(
                path: (workspace / "swift-json").string,
                name: "swift-json",
                product: "JSON",
                imports: ["JSON"]
            ),
            Manifest_Primitives.Manifest.Dependency(
                path: (workspace / "swift-file-system").string,
                name: "swift-file-system",
                product: "File System",
                imports: ["File_System"]
            ),
            Manifest_Primitives.Manifest.Dependency(
                path: linterPath,
                name: "swift-linter",
                product: "Linter",
                imports: ["Linter"]
            ),
        ]
    }
}
