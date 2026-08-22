public import File_System

extension Lint.File.Single {

  public enum State {}
}

extension Lint.File.Single.State {

  public static func directory(consumerPackageRoot: File.Path) -> File.Path {
    consumerPackageRoot / ".swift-lint"
  }

  public static func create(
    consumerPackageRoot: File.Path
  ) throws(Error) -> File.Path {
    let directory: File.Path = Self.directory(consumerPackageRoot: consumerPackageRoot)
    do throws(File.System.Create.Directory.Error) {
      try File.Directory(directory).create.recursive()
    } catch {
      throw .creationFailed(path: directory, description: "\(error)")
    }
    let marker: File.Path = directory / ".gitignore"
    do throws(File.System.Write.Atomic.Error) {
      try File(marker).write.atomic("*\n")
    } catch {
      throw .creationFailed(path: marker, description: "\(error)")
    }
    return directory
  }
}
