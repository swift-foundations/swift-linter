public import File_System

extension Lint.File.Single.State {

  public enum Error: Swift.Error, Equatable, Sendable {
    case creationFailed(path: File.Path, description: Swift.String)
  }
}
