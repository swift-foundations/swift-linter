public import File_System
internal import Version_Primitives

extension Lint.File.Single {

  public enum Detection: Swift.Sendable {}
}

extension Lint.File.Single.Detection {

  public static let header: Swift.String = "swift-linter-tools-version:"

  public static func detect(at consumerPackageRoot: File.Path) -> File.Path? {
    let candidate: File.Path = consumerPackageRoot / "Lint.swift"

    guard File.System.Stat.isFile(at: candidate) else { return nil }
    let source: Swift.String
    do throws(File.System.Read.Full.Error) {
      source = try Lint.File.Single.contents(of: candidate)
    } catch {
      return nil
    }
    return Self.hasMagicComment(in: source) ? candidate : nil
  }

  internal static func hasMagicComment(in source: Swift.String) -> Swift.Bool {
    Self.parseMagicCommentToolsVersion(in: source) != nil
  }

  fileprivate static func parseMagicCommentToolsVersion(
    in source: Swift.String
  ) -> Version.Tools? {
    var lineCount = 0
    for line in source.split(separator: "\n", maxSplits: 30, omittingEmptySubsequences: false) {
      if line.contains(Self.header) {
        let parts = line.split(
          separator: ":",
          maxSplits: 1,
          omittingEmptySubsequences: false
        )
        guard parts.count == 2 else { return nil }
        var versionSlice = parts[1]
        while let first = versionSlice.first, first == " " || first == "\t" {
          versionSlice = versionSlice.dropFirst()
        }
        while let last = versionSlice.last, last == " " || last == "\t" {
          versionSlice = versionSlice.dropLast()
        }
        return Version.Tools(Swift.String(versionSlice))
      }
      lineCount += 1
      if lineCount >= 30 { break }
    }
    return nil
  }
}
