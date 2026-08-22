public import File_System
internal import Manifest_Resolver

extension Lint.Driver {

  public enum Dispatch {}
}

extension Lint.Driver.Dispatch {

  public static func nested(
    at consumerPackageRoot: File.Path,
    arguments: [Swift.String],
    onDispatchError: (Swift.String) -> Void = { _ in }
  ) -> Swift.Int32? {

    let rootString: Swift.String = consumerPackageRoot.string
    guard Manifest_Resolver.Manifest.NestedPackage.detect(at: rootString) else {
      return nil
    }
    do throws(Manifest_Resolver.Manifest.NestedPackage.Error) {
      return try Manifest_Resolver.Manifest.NestedPackage.dispatch(
        at: rootString,
        arguments: arguments
      )
    } catch {
      onDispatchError("\(error)")
      return 1
    }
  }
}
