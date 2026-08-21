internal import File_System

extension Lint.Fix {

    internal enum Publisher {}
}

extension Lint.Fix.Publisher {

    internal static func apply(
        _ changes: [Lint.Fix.Change]
    ) throws(Lint.Run.Error) -> [File.Path] {
        let planned = changes.map(\.path)
        var published: [File.Path] = []
        published.reserveCapacity(changes.count)

        for change in changes {
            let current: Swift.String
            do throws(Lint.Run.Error) {
                current = try Lint.Fix.read(change.path)
            } catch {
                throw .fixPublicationFailed(
                    path: change.path,
                    planned: planned,
                    published: published
                )
            }
            guard current.utf8.elementsEqual(change.original.utf8) else {
                throw .staleFixOriginal(
                    path: change.path,
                    planned: planned,
                    published: published
                )
            }
            do throws(File.System.Write.Atomic.Error) {
                try File(change.path).write.atomic(change.fixed)
            } catch {
                throw .fixPublicationFailed(
                    path: change.path,
                    planned: planned,
                    published: published
                )
            }
            published.append(change.path)
        }
        return published
    }
}
