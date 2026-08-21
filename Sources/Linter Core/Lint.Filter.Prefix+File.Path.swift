public import File_System
public import Linter_Primitives

extension Lint.Filter.Prefix {

    @inlinable
    public init(_ filePath: File.Path) {
        self = Self(filePath.description)
    }
}
