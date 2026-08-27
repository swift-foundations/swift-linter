public import File_System
public import Linter

extension Lint.Filter.Prefix {

  @inlinable
  public init(_ filePath: File.Path) {
    self = Self(filePath.description)
  }
}
