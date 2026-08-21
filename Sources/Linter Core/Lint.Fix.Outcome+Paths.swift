public import File_System

extension Lint.Fix.Outcome {

    public var paths: [File.Path] { changes.map(\.path) }
}
