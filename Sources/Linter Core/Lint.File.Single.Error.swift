public import File_System

extension Lint.File.Single {

    public enum Error: Swift.Error, Swift.Sendable {

        case readFailed(path: File.Path, description: Swift.String)

        case missingToolsVersion(path: File.Path)

        case parseFailed(path: File.Path, description: Swift.String)

        case dependenciesNotFound(path: File.Path, description: Swift.String)

        case malformedPackageCall(path: File.Path, description: Swift.String)

        case materializationFailed(reason: Swift.String)

        case spawnFailed(consumerPackageRoot: File.Path, description: Swift.String)
    }
}
