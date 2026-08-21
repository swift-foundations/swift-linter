public import File_System

extension Lint.File.Single.Channel {

    public enum Error: Swift.Error, Swift.Sendable {

        case invalidPath(variable: Swift.String, raw: Swift.String, description: Swift.String)

        case unreadable(variable: Swift.String, path: File.Path, description: Swift.String)

        case unparseable(variable: Swift.String, path: File.Path, description: Swift.String)

        case writeFailed(variable: Swift.String, description: Swift.String)
    }
}
