public import File_System

extension Lint.Driver {

  public enum Manifest {}
}

extension Lint.Driver.Manifest {

  public static func path(at consumerPackageRoot: File.Path) -> File.Path? {
    let candidate: File.Path = consumerPackageRoot / "Lint.swift"

    return File.System.Stat.isFile(at: candidate) ? candidate : nil
  }
}
