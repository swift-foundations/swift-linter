public import File_System

extension Lint.Run {

    public enum Error: Swift.Error, Hashable, Sendable {
        case fileNotReadable(path: File.Path)
        case nonUTF8(path: File.Path)

        case staleFixOriginal(
            path: File.Path,
            planned: [File.Path],
            published: [File.Path]
        )

        case fixPublicationFailed(
            path: File.Path,
            planned: [File.Path],
            published: [File.Path]
        )
    }
}
