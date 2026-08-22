public import File_System
public import Linter_Primitives

extension Lint.Source.Path {

  @inlinable
  public init(_ filePath: File.Path) {
    self = Self(filePath.description)
  }
}
